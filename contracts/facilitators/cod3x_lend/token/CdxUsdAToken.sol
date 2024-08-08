// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ILendingPool} from "lib/Cod3x-Lend/contracts/interfaces/ILendingPool.sol";
import {IAToken} from "lib/Cod3x-Lend/contracts/interfaces/IAToken.sol";
import {IRewarder} from "lib/Cod3x-Lend/contracts/interfaces/IRewarder.sol";

import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";
import {Errors} from "lib/Cod3x-Lend/contracts/protocol/libraries/helpers/Errors.sol";
import {VersionedInitializable} from
    "lib/Cod3x-Lend/contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {IncentivizedERC20} from
    "lib/Cod3x-Lend/contracts/protocol/tokenization/IncentivizedERC20.sol";
import {ICdxUSD} from "contracts/tokens/interfaces/ICdxUSD.sol";
import {ICdxUsdAToken} from "contracts/tokens/interfaces/ICdxUsdAToken.sol";
import {ICdxUSDFacilitators} from "contracts/tokens/interfaces/ICdxUSDFacilitators.sol";
import {IERC20} from "lib/Cod3x-Lend/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {CdxUsdVariableDebtToken} from "./CdxUsdVariableDebtToken.sol";

/**
 * @title CdxUSD A ERC20 AToken
 * @dev Implementation of the interest bearing token for the Cod3x Lend protocol
 * @author Cod3x - Beirao
 */
contract CdxUsdAToken is
    ICdxUsdAToken,
    VersionedInitializable,
    IncentivizedERC20("ATOKEN_IMPL", "ATOKEN_IMPL", 0)
{
    using WadRayMath for uint256;

    uint256 public constant ATOKEN_REVISION = 0x1;

    ILendingPool internal _pool;
    CdxUsdVariableDebtToken internal _cdxUsdVariableDebtToken;
    address internal _treasury;
    address internal _cdxUsdTreasury;
    address internal _underlyingAsset;
    bool internal _reserveType;
    IRewarder internal _incentivesController;

    modifier onlyLendingPool() {
        require(_msgSender() == address(_pool), Errors.CT_CALLER_MUST_BE_LENDING_POOL);
        _;
    }

    modifier onlyPoolAdmin() {
        require(
            _msgSender() == _pool.getAddressesProvider().getPoolAdmin(),
            Errors.CALLER_NOT_POOL_ADMIN
        );
        _;
    }

    /**
     * @dev Initializes the aToken. MUST also call setVariableDebtToken() at initialization.
     * @param pool The address of the lending pool where this aToken will be used
     * @param treasury The address of the Aave treasury, receiving the fees on this aToken
     * @param underlyingAsset The address of the underlying asset of this aToken (E.g. WETH for aWETH)
     * @param incentivesController The smart contract managing potential incentives distribution
     * @param aTokenDecimals The decimals of the aToken, same as the underlying asset's
     * @param aTokenName The name of the aToken
     * @param aTokenSymbol The symbol of the aToken
     */
    function initialize(
        ILendingPool pool,
        address treasury,
        address underlyingAsset,
        IRewarder incentivesController,
        uint8 aTokenDecimals,
        string calldata aTokenName,
        string calldata aTokenSymbol,
        bytes calldata params
    ) external override initializer {
        _setName(aTokenName);
        _setSymbol(aTokenSymbol);
        _setDecimals(aTokenDecimals);

        _pool = pool;
        _treasury = treasury;
        _underlyingAsset = underlyingAsset;
        _incentivesController = incentivesController;

        _reserveType = true; // @issue was always false, make it configurable or always true ?

        emit Initialized(
            underlyingAsset,
            address(pool),
            treasury,
            address(incentivesController),
            aTokenDecimals,
            aTokenName,
            aTokenSymbol,
            params
        );
    }

    /// @inheritdoc ICdxUsdAToken
    function setVariableDebtToken(address cdxUsdVariableDebtToken)
        external
        override
        onlyPoolAdmin
    {
        require(address(_cdxUsdVariableDebtToken) == address(0), "VARIABLE_DEBT_TOKEN_ALREADY_SET");
        require(cdxUsdVariableDebtToken != address(0), "ZERO_INPUT");

        _cdxUsdVariableDebtToken = CdxUsdVariableDebtToken(cdxUsdVariableDebtToken);
        emit VariableDebtTokenSet(cdxUsdVariableDebtToken);
    }

    /**
     * @dev Burns aTokens from `user` and sends the equivalent amount of underlying to `receiverOfUnderlying`
     * - Only callable by the LendingPool, as extra state updates there need to be managed
     */
    function burn(address, address, uint256, uint256) external override onlyLendingPool {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @dev Mints `amount` aTokens to `user`
     * - Only callable by the LendingPool, as extra state updates there need to be managed
     * @return `true` if the the previous balance of the user was 0
     */
    function mint(address, uint256, uint256) external override onlyLendingPool returns (bool) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @dev Mints aTokens to the reserve treasury
     * - Only callable by the LendingPool
     */
    function mintToTreasury(uint256, uint256) external override onlyLendingPool {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @dev Transfers aTokens in the event of a borrow being liquidated, in case the liquidators reclaims the aToken
     * - Only callable by the LendingPool
     */
    function transferOnLiquidation(address, address, uint256) external override onlyLendingPool {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @dev Calculates the balance of the user: principal balance + interest generated by the principal
     * @return The balance of the user
     *
     */
    function balanceOf(address) public view override(IncentivizedERC20, IERC20) returns (uint256) {
        return 0;
    }

    /**
     * @dev Returns the scaled balance of the user. The scaled balance is the sum of all the
     * updated stored balance divided by the reserve's liquidity index at the moment of the update
     * @param user The user whose balance is calculated
     * @return The scaled balance of the user
     *
     */
    function scaledBalanceOf(address user) external view override returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @dev Returns the scaled balance of the user and the scaled total supply.
     * @param user The address of the user
     * @return The scaled balance of the user
     * @return The scaled balance and the scaled total supply
     *
     */
    function getScaledUserBalanceAndSupply(address user)
        external
        view
        override
        returns (uint256, uint256)
    {
        return (super.balanceOf(user), super.totalSupply());
    }

    /**
     * @dev calculates the total supply of the specific aToken
     * since the balance of every single user increases over time, the total supply
     * does that too.
     * @return the current total supply
     *
     */
    function totalSupply() public view override(IncentivizedERC20, IERC20) returns (uint256) {
        return 0;
    }

    /**
     * @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
     * @return the scaled total supply
     *
     */
    function scaledTotalSupply() public view virtual override returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @dev Returns the address of the Aave treasury, receiving the fees on this aToken
     *
     */
    function RESERVE_TREASURY_ADDRESS() public view returns (address) {
        return _treasury;
    }

    /**
     * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     *
     */
    function UNDERLYING_ASSET_ADDRESS() public view override returns (address) {
        return _underlyingAsset;
    }

    /**
     * @dev Returns the address of the lending pool where this aToken is used
     *
     */
    function POOL() public view returns (ILendingPool) {
        return _pool;
    }

    /**
     * @dev For internal usage in the logic of the parent contract IncentivizedERC20
     *
     */
    function _getIncentivesController() internal view override returns (IRewarder) {
        return _incentivesController;
    }

    /**
     * @dev Returns the address of the incentives controller contract
     *
     */
    function getIncentivesController() external view override returns (IRewarder) {
        return _getIncentivesController();
    }

    /**
     * @dev Transfers the underlying asset to `target`. Used by the LendingPool to transfer
     * assets in borrow(), withdraw() and flashLoan()
     * @param target The recipient of the aTokens
     * @param amount The amount getting transferred
     * @return The amount transferred
     *
     */
    function transferUnderlyingTo(address target, uint256 amount)
        external
        override
        onlyLendingPool
        returns (uint256)
    {
        ICdxUSD(_underlyingAsset).mint(target, amount);
        return amount;
    }

    /**
     * @dev Invoked to execute actions on the aToken side after a repayment.
     * @param user The user executing the repayment
     * @param amount The amount getting repaid
     */
    function handleRepayment(address user, address onBehalfOf, uint256 amount)
        external
        override
        onlyLendingPool
    {
        uint256 balanceFromInterest = _cdxUsdVariableDebtToken.getBalanceFromInterest(onBehalfOf);
        if (amount <= balanceFromInterest) {
            _cdxUsdVariableDebtToken.decreaseBalanceFromInterest(onBehalfOf, amount);
        } else {
            _cdxUsdVariableDebtToken.decreaseBalanceFromInterest(onBehalfOf, balanceFromInterest);
            ICdxUSD(_underlyingAsset).burn(amount - balanceFromInterest);
        }
    }

    /**
     * @dev implements the permit function
     */
    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @dev Overrides the parent _transfer to force validated transfer() and transferFrom()
     */
    function _transfer(address, address, uint256) internal override {
        revert("OPERATION_NOT_SUPPORTED");
    }

    function setIncentivesController(address incentivesController)
        external
        override
        onlyLendingPool
    {
        require(incentivesController != address(0), "85");
        _incentivesController = IRewarder(incentivesController);
    }

    function rebalance() external override onlyLendingPool {
        revert("OPERATION_NOT_SUPPORTED");
    }

    function getPool() external view returns (address) {
        return address(_pool);
    }

    function getRevision() internal pure virtual override returns (uint256) {
        return ATOKEN_REVISION;
    }

    /// @inheritdoc ICdxUsdAToken
    function getVariableDebtToken() external view override returns (address) {
        return address(_cdxUsdVariableDebtToken);
    }

    /// @inheritdoc ICdxUSDFacilitators
    function distributeFeesToTreasury() external virtual override {
        require(_cdxUsdTreasury != address(0), "NO_CDXUSD_TREASURY");
        uint256 balance = IERC20(_underlyingAsset).balanceOf(address(this));
        IERC20(_underlyingAsset).transfer(_cdxUsdTreasury, balance);
        emit FeesDistributedToTreasury(_cdxUsdTreasury, _underlyingAsset, balance);
    }

    /// @inheritdoc ICdxUSDFacilitators
    function updateCdxUsdTreasury(address newCdxUsdTreasury) external override onlyPoolAdmin {
        require(newCdxUsdTreasury != address(0), "ZERO_INPUT");
        address oldCdxUsdTreasury = _cdxUsdTreasury;
        _cdxUsdTreasury = newCdxUsdTreasury;
        emit CdxUsdTreasuryUpdated(oldCdxUsdTreasury, newCdxUsdTreasury);
    }

    function setTreasury(address newTreasury) external override onlyLendingPool {
        require(newTreasury != address(0), "ZERO_INPUT");
        _treasury = newTreasury;
    }

    /// @inheritdoc ICdxUSDFacilitators
    function getCdxUsdTreasury() external view override returns (address) {
        return _cdxUsdTreasury;
    }

    /// overrides
    function getTotalManagedAssets() external view override returns (uint256) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    function setFarmingPct(uint256) external override {
        revert("OPERATION_NOT_SUPPORTED");
    }

    function setClaimingThreshold(uint256) external override {
        revert("OPERATION_NOT_SUPPORTED");
    }

    function setFarmingPctDrift(uint256) external override {
        revert("OPERATION_NOT_SUPPORTED");
    }

    function setProfitHandler(address) external override {
        revert("OPERATION_NOT_SUPPORTED");
    }

    function setVault(address) external override {
        revert("OPERATION_NOT_SUPPORTED");
    }
}
