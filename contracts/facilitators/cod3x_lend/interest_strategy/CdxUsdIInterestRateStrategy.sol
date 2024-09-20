// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

/// Cod3x Lend imports
import {IReserveInterestRateStrategy} from
    "lib/Cod3x-Lend/contracts/interfaces/IReserveInterestRateStrategy.sol";
import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";
import {PercentageMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/PercentageMath.sol";
import {ILendingPoolAddressesProvider} from
    "lib/Cod3x-Lend/contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {IAToken} from "lib/Cod3x-Lend/contracts/interfaces/IAToken.sol";
import {IVariableDebtToken} from "lib/Cod3x-Lend/contracts/interfaces/IVariableDebtToken.sol";
import {VariableDebtToken} from
    "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import {ILendingPool} from "lib/Cod3x-Lend/contracts/interfaces/ILendingPool.sol";
import {DataTypes} from "lib/Cod3x-Lend/contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from
    "lib/Cod3x-Lend/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

/// Balancer Imports
import {
    IVault as IBalancerVault,
    JoinKind,
    ExitKind,
    SwapKind
} from "contracts/staking_module/vault_strategy/interfaces/IVault.sol";
import {IAsset} from "node_modules/@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import "contracts/staking_module/vault_strategy/interfaces/IBaseBalancerPool.sol";
import "contracts/staking_module/vault_strategy/libraries/BalancerHelper.sol";

// OZ imports
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Chainlink
import {IAggregatorV3Interface} from "./interfaces/IAggregatorV3Interface.sol";

/**
 * @title CdxUsdIInterestRateStrategy contract
 * @notice Implements the calculation of the interest rates using control theory.
 * @dev The model of interest rate is based Proportional Integrator (PI).
 * Admin needs to set an optimal utilization rate and this strategy will automatically
 * automatically adjust the interest rate according to the `Ki` variable.
 * The controller error is calculated using the balance of the Balancer stable swap
 * incentivized by the sdcxUSD staking module. (see staking_module/)
 * Reference: https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4844212
 * @dev ATTENTION, this contract must no be used as a library. One CdxUsdIInterestRateStrategy
 * needs to be associated with only one market.
 * @author Cod3x - Beirao
 */
contract CdxUsdIInterestRateStrategy is IReserveInterestRateStrategy {
    using WadRayMath for uint256;
    using WadRayMath for int256;
    using PercentageMath for uint256;

    int256 private constant RAY = 1e27;
    uint256 private constant SCALING_DECIMAL = 18;

    ILendingPoolAddressesProvider public immutable _addressesProvider;
    address public immutable _asset; // (cdxUSD) This strategy contract needs to be associated to a unique market.
    bool public immutable _assetReserveType; // This strategy contract needs to be associated to a unique market.

    IBalancerVault public immutable _balancerVault;
    bytes32 public _poolId;
    IERC20[] public /* immutable */ stablePoolTokens; // most of the time [cdxUSD, USDC/USDT] (order can change)

    int256 public _minControllerError;
    uint256 public _optimalStablePoolReserveUtilization;
    uint256 public _manualInterestRate;

    // Oracle
    IAggregatorV3Interface public _counterAssetPriceFeed;
    int256 public _priceFeedReference;
    uint256 public _pegMargin;
    uint256 public _timeout;

    // I
    uint256 public _ki; // in RAY
    uint256 public _lastTimestamp;
    int256 public _errI;

    // Errors
    error PiReserveInterestRateStrategy__ACCESS_RESTRICTED_TO_LENDING_POOL();
    error PiReserveInterestRateStrategy__ACCESS_RESTRICTED_TO_POOL_ADMIN();
    error PiReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();
    error PiReserveInterestRateStrategy__RATE_MORE_THAN_100();
    error PiReserveInterestRateStrategy__ZERO_INPUT();
    error PiReserveInterestRateStrategy__BALANCER_POOL_NOT_COMPATIBLE();

    // Events
    event PidLog( // if stablePoolReserveUtilization == 0 => counter asset deppeged.
        uint256 currentVariableBorrowRate,
        uint256 stablePoolReserveUtilization,
        int256 err,
        int256 controllerErr
    );

    /// @dev `setOracleValues()` needs to be called at contracts creation.
    //! The counter asset MUST be a 1$ pegged asset
    constructor(
        address provider,
        address asset, // cdxUSD
        bool assetReserveType, // true
        address balancerVault,
        bytes32 poolId,
        int256 minControllerError,
        int256 initialErrIValue,
        uint256 ki
    ) {
        /// Cod3x Lend
        _asset = asset;
        _assetReserveType = assetReserveType;
        _addressesProvider = ILendingPoolAddressesProvider(provider);

        /// PID values
        _ki = ki;
        _lastTimestamp = block.timestamp;
        _minControllerError = minControllerError;

        // Balancer
        _balancerVault = IBalancerVault(balancerVault);
        _poolId = poolId;
        (IERC20[] memory tokens,,) = IBalancerVault(balancerVault).getPoolTokens(poolId); //? is returning an array with BPT token?
        (address pool,) = IBalancerVault(balancerVault).getPool(poolId);
        tokens = BalancerHelper._dropBptItem(tokens, pool);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token_ = tokens[i];
            stablePoolTokens.push(token_);
        }
        _optimalStablePoolReserveUtilization = uint256(RAY) / tokens.length;

        /// Checks
        if (minControllerError <= 0) {
            revert PiReserveInterestRateStrategy__ZERO_INPUT();
        }

        if ((transferFunction(initialErrIValue) > uint256(RAY))) {
            revert PiReserveInterestRateStrategy__RATE_MORE_THAN_100();
        }

        _errI = initialErrIValue;

        (IERC20[] memory poolTokens,,) = _balancerVault.getPoolTokens(poolId);

        // 3 tokens [asset, counterAsset, BPT]
        if (poolTokens.length != 3) {
            revert PiReserveInterestRateStrategy__BALANCER_POOL_NOT_COMPATIBLE();
        }

        if (
            address(poolTokens[0]) != asset && address(poolTokens[1]) != asset
                && address(poolTokens[2]) != asset
        ) {
            revert PiReserveInterestRateStrategy__BALANCER_POOL_NOT_COMPATIBLE();
        }
    }

    modifier onlyPoolAdmin() {
        if (msg.sender != _addressesProvider.getPoolAdmin()) {
            revert PiReserveInterestRateStrategy__ACCESS_RESTRICTED_TO_POOL_ADMIN();
        }
        _;
    }

    modifier onlyLendingPool() {
        if (msg.sender != _addressesProvider.getLendingPool()) {
            revert PiReserveInterestRateStrategy__ACCESS_RESTRICTED_TO_LENDING_POOL();
        }
        _;
    }

    // ----------- admin -----------

    /**
     * @notice Sets the minimum controller error.
     * @dev Only the admin can call this function.
     * @param minControllerError The new minimum controller error value.
     */
    function setMinControllerError(int256 minControllerError) external onlyPoolAdmin {
        if (minControllerError <= 0) {
            revert PiReserveInterestRateStrategy__ZERO_INPUT();
        }

        _minControllerError = minControllerError;
    }

    /**
     * @notice Sets the PID values for the controller.
     * @dev Only the admin can call this function.
     * @param ki The proportional gain value.
     */
    function setPidValues(uint256 ki, int256 maxITimeAmp) external onlyPoolAdmin {
        if (ki == 0 || maxITimeAmp == 0) {
            revert PiReserveInterestRateStrategy__ZERO_INPUT();
        }

        _ki = ki;
    }

    /**
     * @notice Sets the oracle values for the controller.
     * @dev Only the admin can call this function.
     * @param counterAssetPriceFeed The address of the COUNTER ASSET price feed.
     * @param pegMargin The margin for the peg value in RAY.
     * @param timeout Pricefeed timeout to know if the price feed is frozen.
     */
    function setOracleValues(address counterAssetPriceFeed, uint256 pegMargin, uint256 timeout)
        external
        onlyPoolAdmin
    {
        _counterAssetPriceFeed = IAggregatorV3Interface(counterAssetPriceFeed);
        _priceFeedReference = int256(1 * 10 ** uint256(_counterAssetPriceFeed.decimals()));
        _pegMargin = pegMargin;
        _timeout = timeout;
    }

    /**
     * @notice Sets the poolId variable.
     * @dev Only the admin can call this function.
     * @param newPoolId The new Balancer pool id.
     */
    function setBalancerPoolId(bytes32 newPoolId) external onlyPoolAdmin {
        if (newPoolId == bytes32(0)) {
            revert PiReserveInterestRateStrategy__ZERO_INPUT();
        }
        _poolId = newPoolId;
    }

    /**
     * @notice Sets the interest rate manually. When _manualInterestRate != 0, this contract
     *         overrides the I controller.
     * @dev Only the admin can call this function.
     * @param manualInterestRate Manual interest rate value to be set. (in RAY)
     */
    function setManualInterestRate(uint256 manualInterestRate) external onlyPoolAdmin {
        if (manualInterestRate > uint256(RAY)) {
            revert PiReserveInterestRateStrategy__RATE_MORE_THAN_100();
        }
        _manualInterestRate = manualInterestRate;
    }

    /**
     * @notice Overrides the I controller value.
     * @dev Only the admin can call this function.
     * @param newErrI New _errI value. (in RAY)
     */
    function setErrI(int256 newErrI) external onlyPoolAdmin {
        if (transferFunction(newErrI) > uint256(RAY)) {
            revert PiReserveInterestRateStrategy__RATE_MORE_THAN_100();
        }
        _errI = newErrI;
    }

    // ----------- external -----------

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations
     * @return The liquidity rate and the variable borrow rate
     */
    function calculateInterestRates(address, address, uint256, uint256, uint256, uint256)
        external
        override
        onlyLendingPool
        returns (uint256, uint256)
    {
        return calculateInterestRates(address(0), 0, 0, 0);
    }

    /**
     * @dev Calculates the interest rates depending on the reserve's state and configurations.
     * NOTE This function is kept for compatibility with the previous DefaultInterestRateStrategy interface.
     * New protocol implementation uses the new calculateInterestRates() interface
     * @return The liquidity rate and the variable borrow rate
     */
    function calculateInterestRates(address, uint256, uint256, uint256)
        internal
        returns (uint256, uint256)
    {
        uint256 stablePoolReserveUtilization;

        if (address(_counterAssetPriceFeed) == address(0) || isCounterAssetPegged()) {
            /// Calculate the cdxUSD stablePool reserve utilization
            stablePoolReserveUtilization = getCdxUsdStablePoolReserveUtilization();

            /// PID state update
            int256 err = getNormalizedError(stablePoolReserveUtilization);
            _errI += int256(_ki).rayMulInt(err * int256(block.timestamp - _lastTimestamp));
            if(_errI < 0) _errI = 0; // Limit the negative accumulation.
            _lastTimestamp = block.timestamp;
        }

        uint256 currentVariableBorrowRate =
            _manualInterestRate != 0 ? _manualInterestRate : transferFunction(_errI); // unsafe cast ok.

        emit PidLog(currentVariableBorrowRate, stablePoolReserveUtilization, _errI, _errI);

        return (0, currentVariableBorrowRate);
    }

    // ----------- view -----------

    /**
     * @notice The view version of `calculateInterestRates()`.
     * @dev This function return the current interest rate. Frontend may need to
     * read PidLog to get the last interest rate.
     * @return currentLiquidityRate
     * @return currentVariableBorrowRate
     * @return utilizationRate
     */
    function getCurrentInterestRates() external view returns (uint256, uint256, uint256) {
        return (
            0,
            _manualInterestRate != 0 ? _manualInterestRate : transferFunction(_errI), // _errI == controler error
            0
        );
    }

    function baseVariableBorrowRate() public view override returns (uint256) {
        return uint256(transferFunction(type(int256).min));
    }

    function getMaxVariableBorrowRate() external pure override returns (uint256) {
        return uint256(type(int256).max);
    }

    // ----------- helpers -----------
    /**
     * @notice Helps calculate the cdxUSD balance share in the Balancer Pool.
     * @return return the share (in RAY) of the cdxUSD balance.
     */
    function getCdxUsdStablePoolReserveUtilization() public view returns (uint256) {
        uint256 totalInPool_;
        uint256 cdxUsdAmtInPool_;

        for (uint256 i = 0; i < stablePoolTokens.length; i++) {
            IERC20 token_ = stablePoolTokens[i];
            (uint256 cash_,,,) = IBalancerVault(_balancerVault).getPoolTokenInfo(_poolId, token_);
            cash_ = scaleDecimals(cash_, token_);
            totalInPool_ += cash_;

            if (address(token_) == _asset) cdxUsdAmtInPool_ = cash_;
        }

        return cdxUsdAmtInPool_ * uint256(RAY) / totalInPool_;
    }

    /**
     * @notice Scales an amount to the appropriate number of decimals (18) based on the token's decimal precision.
     * @param amount The value representing the amount to be scaled.
     * @param token The address of the IERC20 token contract.
     * @return The scaled amount.
     */
    function scaleDecimals(uint256 amount, IERC20 token) internal view returns (uint256) {
        return amount * 10 ** (SCALING_DECIMAL - ERC20(address(token)).decimals());
    }

    /**
     * @dev normalize the err:
     * stablePoolReserveUtilization ⊂ [0, Uo]   => err ⊂ [-RAY, 0]
     * stablePoolReserveUtilization ⊂ [Uo, RAY] => err ⊂ [0, RAY]
     * With Uo = optimalStablePoolReserveUtilization
     */
    function getNormalizedError(uint256 stablePoolReserveUtilization)
        internal
        view
        returns (int256)
    {
        int256 err =
            int256(stablePoolReserveUtilization) - int256(_optimalStablePoolReserveUtilization);

        if (int256(stablePoolReserveUtilization) < int256(_optimalStablePoolReserveUtilization)) {
            return err.rayDivInt(int256(_optimalStablePoolReserveUtilization));
        } else {
            return err.rayDivInt(RAY - int256(_optimalStablePoolReserveUtilization));
        }
    }

    /// @dev Transfer Function for calculation of _currentVariableBorrowRate.
    function transferFunction(int256 controllerError) public view returns (uint256) {
        return
            uint256(controllerError > _minControllerError ? controllerError : _minControllerError);
    }

    /// @dev Return `true` if the counter asset is pegged. Uses the `_pegMargin` to determine.
    function isCounterAssetPegged() public view returns (bool) {
        try _counterAssetPriceFeed.latestRoundData() returns (
            uint80 roundID, int256 answer, uint256 startedAt, uint256 timestamp, uint80
        ) {
            // Chainlink integrity checks
            if (
                roundID == 0 || timestamp == 0 || timestamp > block.timestamp || answer < 0
                    || startedAt == 0 || block.timestamp - timestamp > _timeout
            ) {
                return false;
            }

            // Peg check
            if (abs(RAY - answer * RAY / _priceFeedReference) > _pegMargin) return false;

            return true;
        } catch {
            return false;
        }
    }

    function abs(int256 x) private pure returns (uint256) {
        return x < 0 ? uint256(-x) : uint256(x);
    }
}
