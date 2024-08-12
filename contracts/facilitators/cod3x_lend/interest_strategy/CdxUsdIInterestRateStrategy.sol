// SPDX-License-Identifier: MIT
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
    "lib/Cod3x-Lend/contracts/protocol/tokenization/VariableDebtToken.sol";
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
import "@openzeppelin/contracts/access/Ownable.sol";

// Chainlink
import {IAggregatorV3Interface} from "./interfaces/IAggregatorV3Interface.sol";

/// TODOs
// - _errI in constructor
// - tests
import "forge-std/console.sol";

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
contract CdxUsdIInterestRateStrategy is IReserveInterestRateStrategy, Ownable {
    using WadRayMath for uint256;
    using WadRayMath for int256;
    using PercentageMath for uint256;

    ILendingPoolAddressesProvider public immutable _addressesProvider;
    address public immutable _asset; // (cdxUSD) This strategy contract needs to be associated to a unique market.
    bool public immutable _assetReserveType; // This strategy contract needs to be associated to a unique market.

    IBalancerVault public immutable _balancerVault; //? make it non immutable
    bytes32 public immutable _poolId; //? make it non immutable
    IERC20[] public /* immutable */ stablePoolTokens; // most of the time [cdxUSD, USDC/USDT] (order can change)

    int256 public constant ALPHA = 15e25; // 15e(-2)
    int256 private constant RAY = 1e27;
    uint256 private constant SCALING_DECIMAL = 18;

    int256 public _minControllerError;
    int256 public _maxErrIAmp;
    uint256 public _optimalStablePoolReserveUtilization;

    // Oracle
    IAggregatorV3Interface public _counterAssetPriceFeed;
    int256 public _priceFeedReference;
    uint256 public _pegMargin;
    uint256 public _timeout;

    // P - to disable
    uint256 public _kp;

    // I
    uint256 public _ki; // in RAY
    uint256 public _lastTimestamp;
    int256 public _errI;

    // Errors
    error PiReserveInterestRateStrategy__ACCESS_RESTRICTED_TO_LENDING_POOL();
    error PiReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();

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
        int256 maxITimeAmp,
        uint256 ki,
        address admin
    ) Ownable(admin) {
        /// Cod3x Lend
        _asset = asset;
        _assetReserveType = assetReserveType;
        _addressesProvider = ILendingPoolAddressesProvider(provider);

        /// PID values
        _kp = 0;
        _ki = ki;
        _lastTimestamp = block.timestamp;
        _minControllerError = minControllerError;
        _maxErrIAmp = int256(_ki).rayMulInt(-RAY * maxITimeAmp);

        // Balancer
        _balancerVault = IBalancerVault(balancerVault);
        _poolId = poolId;
        (IERC20[] memory tokens,,) = IBalancerVault(balancerVault).getPoolTokens(poolId); //? is returning an array with BPT token?
        console.log("Length: ", tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            console.log("First tokens: ", address(tokens[i]));
        }
        // (address pool,) = IBalancerVault(balancerVault).getPool(poolId);
        // tokens = BalancerHelper._dropBptItem(tokens, pool);
        // for (uint256 i = 0; i < tokens.length; i++) {
        //     console.log("Second tokens: ", address(tokens[i]));
        // }
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token_ = tokens[i];
            stablePoolTokens.push(token_);
        }
        _optimalStablePoolReserveUtilization = uint256(RAY) / tokens.length;

        /// Checks
        if (transferFunction(type(int256).min) < 0) {
            revert PiReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();
        }

        _errI = 13e19 * 1000000;
        // TODO checks
        // - _balancerVault and poolId compatibility with other contracts.
        // - check minium pool balance
        // - check the pool is fairly balanced (50/50)
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
    function setMinControllerError(int256 minControllerError) external onlyOwner {
        _minControllerError = minControllerError;
        if (transferFunction(type(int256).min) < 0) {
            revert PiReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();
        }
    }

    /**
     * @notice Sets the PID values for the controller.
     * @dev Only the admin can call this function.
     * @param ki The proportional gain value.
     * @param maxITimeAmp The maximum integral time amplification value.
     */
    function setPidValues(uint256 ki, int256 maxITimeAmp) external onlyOwner {
        _ki = ki;
        _maxErrIAmp = int256(_ki).rayMulInt(-RAY * maxITimeAmp);
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
        onlyOwner
    {
        _counterAssetPriceFeed = IAggregatorV3Interface(counterAssetPriceFeed);
        _priceFeedReference = int256(10 ** uint256(_counterAssetPriceFeed.decimals()));
        _pegMargin = pegMargin;
        _timeout = timeout;
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
            console.log("stablePoolReserveUtilization ", stablePoolReserveUtilization);

            /// PID state update
            int256 err = getNormalizedError(stablePoolReserveUtilization);
            _errI += int256(_ki).rayMulInt(err * int256(block.timestamp - _lastTimestamp));
            if (_errI < _maxErrIAmp) _errI = _maxErrIAmp; // Limit _errI negative accumulation.
            _lastTimestamp = block.timestamp;
        }

        uint256 currentVariableBorrowRate = transferFunction(_errI);

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
        // console.log("Utilization rate: ", getCdxUsdStablePoolReserveUtilization());
        uint256 utilizationRate = getCdxUsdStablePoolReserveUtilization();
        int256 normalizedError = getNormalizedError(utilizationRate);
        console.log("Normalized: ", uint256(normalizedError));
        return (0, transferFunction(getControllerError(normalizedError)), utilizationRate);
    }

    function baseVariableBorrowRate() public view override returns (uint256) {
        return uint256(transferFunction(type(int256).min));
    }

    function getMaxVariableBorrowRate() external pure override returns (uint256) {
        return type(uint256).max;
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
            console.log("Cash for %s: %s", address(token_), cash_);
            cash_ = scaleDecimals(cash_, token_);
            totalInPool_ += cash_;

            if (address(token_) == _asset) cdxUsdAmtInPool_ = cash_;
        }
        console.log("totalInPool_: ", totalInPool_);
        console.log("cdxUsdAmtInPool_: ", cdxUsdAmtInPool_);
        console.log("utilization rate: ", cdxUsdAmtInPool_ * uint256(RAY) / totalInPool_);
        return cdxUsdAmtInPool_ * uint256(RAY) / totalInPool_;
    }

    /**
     * @notice Scales an amount to the appropriate number of decimals (18) based on the token's decimal precision.
     * @param amount The value representing the amount to be scaled.
     * @param token The address of the IERC20 token contract.
     * @return The scaled amount.
     */
    function scaleDecimals(uint256 amount, IERC20 token) internal view returns (uint256) {
        console.log("Decimals: ", ERC20(address(token)).decimals());
        console.log("Multiplications: ", (SCALING_DECIMAL - ERC20(address(token)).decimals()));
        console.log(
            "Returning: ", amount * 10 ** (SCALING_DECIMAL - ERC20(address(token)).decimals())
        );
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
        console.log(
            "_optimalStablePoolReserveUtilization %s vs stablePoolReserveUtilization %s",
            _optimalStablePoolReserveUtilization,
            stablePoolReserveUtilization
        );
        int256 err =
            int256(stablePoolReserveUtilization) - int256(_optimalStablePoolReserveUtilization);
        console.log("ERROR: ", uint256(err));
        if (int256(stablePoolReserveUtilization) < int256(_optimalStablePoolReserveUtilization)) {
            console.log(
                "Return err 1: ",
                uint256(err.rayDivInt(int256(_optimalStablePoolReserveUtilization)))
            );
            return err.rayDivInt(int256(_optimalStablePoolReserveUtilization));
        } else {
            console.log(
                "Return err 2: ",
                uint256(err.rayDivInt(RAY - int256(_optimalStablePoolReserveUtilization)))
            );
            return err.rayDivInt(RAY - int256(_optimalStablePoolReserveUtilization));
        }
    }

    /// @dev Process the controller error from the normalized error.
    function getControllerError(int256 err) internal view returns (int256) {
        int256 errP = int256(_kp).rayMulInt(err);
        console.log("errP: ", uint256(errP));
        console.log("errI: ", uint256(_errI));
        console.log("Sum: ", uint256(errP + _errI));
        return errP + _errI;
    }

    /// @dev Transfer Function for calculation of _currentVariableBorrowRate (https://www.desmos.com/calculator/dj5puy23wz)
    function transferFunction(int256 controllerError) public view returns (uint256) {
        int256 ce = controllerError > _minControllerError ? controllerError : _minControllerError;
        console.log("ce: ", uint256(ce));
        console.log("RAY - ce: ", uint256(RAY - ce));
        return uint256(ALPHA.rayMulInt(ce.rayDivInt(RAY - ce)));
    }

    /// @dev Return `true` if the counter asset is pegged. Uses the `_pegMargin` to determine.
    function isCounterAssetPegged() public returns (bool) {
        try _counterAssetPriceFeed.latestRoundData() returns (
            uint80 roundID, int256 answer, uint256 startedAt, uint256 timestamp, uint80
        ) {
            ///? Chainlink integrity checks
            // if (
            //     roundID == 0 || timestamp == 0 || timestamp > block.timestamp || answer < 0
            //         || startedAt == 0 || block.timestamp - timestamp > _timeout
            // ) {
            //     return false;
            // }

            console.log("answer ", uint256(answer));
            console.log("_priceFeedReference ", uint256(_priceFeedReference));
            console.log("ref ", uint256(abs(RAY - answer * RAY / _priceFeedReference)));

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
