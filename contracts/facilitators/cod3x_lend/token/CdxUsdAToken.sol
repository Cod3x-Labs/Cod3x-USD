// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {ILendingPool} from "lib/Cod3x-Lend/contracts/interfaces/ILendingPool.sol";
import {IAToken} from "lib/Cod3x-Lend/contracts/interfaces/IAToken.sol";
import {IRewarder} from "lib/Cod3x-Lend/contracts/interfaces/IRewarder.sol";

import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";
import {Errors} from "lib/Cod3x-Lend/contracts/protocol/libraries/helpers/Errors.sol";
import {VersionedInitializable} from
    "lib/Cod3x-Lend/contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {IncentivizedERC20} from
    "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC20/IncentivizedERC20.sol";
import {ICdxUSD} from "contracts/interfaces/ICdxUSD.sol";
import {ICdxUsdAToken} from "contracts/interfaces/ICdxUsdAToken.sol";
import {ICdxUSDFacilitators} from "contracts/interfaces/ICdxUSDFacilitators.sol";
import {IERC20} from "lib/Cod3x-Lend/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {CdxUsdVariableDebtToken} from "./CdxUsdVariableDebtToken.sol";
import {IRollingRewarder} from "contracts/interfaces/IRollingRewarder.sol";

/**
 * @title CdxUSD A ERC20 AToken
 * @notice Implementation of the interest bearing token for the Cod3x Lend protocol.
 * @author Cod3x - Beirao
 * @dev This contract represents the interest-bearing version of CdxUSD in the Cod3x Lend protocol.
 * It tracks user deposits and accrues interest over time.
 */
contract CdxUsdAToken is
    IncentivizedERC20("ATOKEN_IMPL", "ATOKEN_IMPL", 0),
    VersionedInitializable,
    ICdxUsdAToken
{
    using WadRayMath for uint256;

    /// @dev Tracks contract version for upgrades. Current version is 0x1.
    uint256 public constant ATOKEN_REVISION = 0x1;

    /// @dev Used for percentage calculations. 10000 basis points = 100%.
    uint256 internal constant BPS = 10_000;

    /// @dev Core lending pool contract that manages lending/borrowing operations.
    ILendingPool internal _pool;

    /// @dev Associated variable debt token tracking borrowed amounts.
    CdxUsdVariableDebtToken internal _cdxUsdVariableDebtToken;

    /// @dev Privileged address that can perform maintenance operations.
    address internal _keeper;

    /// @dev Address receiving protocol fees.
    address internal _treasury;

    /// @dev The CdxUSD token this aToken represents.
    address internal _underlyingAsset;

    /// @dev Indicates reserve type configuration.
    bool internal _reserveType;

    /// @dev Manages distribution of protocol incentives.
    IRewarder internal _incentivesController;

    /// @dev Manages CdxUSD rewards in the Reliquary system.
    IRollingRewarder public _reliquaryCdxusdRewarder;

    /// @dev Percentage of fees allocated to Reliquary, in basis points.
    uint256 public _reliquaryAllocation;

    /// @dev Restricts function access to only the lending pool contract.
    modifier onlyLendingPool() {
        require(msg.sender == address(_pool), Errors.AT_CALLER_MUST_BE_LENDING_POOL);
        _;
    }

    /// @dev Restricts function access to only the pool admin.
    modifier onlyPoolAdmin() {
        require(
            msg.sender == _pool.getAddressesProvider().getPoolAdmin(),
            Errors.VL_CALLER_NOT_POOL_ADMIN
        );
        _;
    }

    /// @dev Restricts function access to only the keeper address.
    modifier onlyKeeper() {
        require(msg.sender == _keeper, Errors.AT_CALLER_NOT_KEEPER);
        _;
    }

    /// @dev Prevents initialization during construction.
    constructor() {
        _blockInitializing();
    }

    /**
     * @notice Sets up the aToken with initial configuration.
     * @dev Must call setVariableDebtToken(), setReliquaryInfo(), and setKeeper() after init.
     * @param pool The lending pool contract address.
     * @param treasury Address receiving protocol fees.
     * @param underlyingAsset The CdxUSD token address.
     * @param incentivesController Contract managing reward distributions.
     * @param aTokenDecimals Decimal places, matching underlying asset.
     * @param aTokenName Token name.
     * @param aTokenSymbol Token symbol.
     */
    function initialize(
        ILendingPool pool,
        address treasury,
        address underlyingAsset,
        IRewarder incentivesController,
        uint8 aTokenDecimals,
        bool,
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

        _reserveType = false;

        emit Initialized(
            underlyingAsset,
            address(pool),
            address(0),
            _treasury,
            address(incentivesController),
            aTokenDecimals,
            _reserveType,
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
        require(address(_cdxUsdVariableDebtToken) == address(0), Errors.AT_DEBT_TOKEN_ALREADY_SET);
        require(cdxUsdVariableDebtToken != address(0), Errors.VL_INVALID_INPUT);

        _cdxUsdVariableDebtToken = CdxUsdVariableDebtToken(cdxUsdVariableDebtToken);

        emit SetVariableDebtToken(cdxUsdVariableDebtToken);
    }

    /// @inheritdoc ICdxUsdAToken
    function setReliquaryInfo(address reliquaryCdxusdRewarder, uint256 reliquaryAllocation)
        external
        override
        onlyPoolAdmin
    {
        require(reliquaryCdxusdRewarder != address(0), Errors.VL_INVALID_INPUT);
        require(reliquaryAllocation <= BPS, Errors.AT_RELIQUARY_ALLOCATION_MORE_THAN_100);

        _reliquaryCdxusdRewarder = IRollingRewarder(reliquaryCdxusdRewarder);
        _reliquaryAllocation = reliquaryAllocation;

        IERC20(_underlyingAsset).approve(reliquaryCdxusdRewarder, type(uint256).max);

        emit SetReliquaryInfo(reliquaryCdxusdRewarder, reliquaryAllocation);
    }

    /// @inheritdoc ICdxUsdAToken
    function setKeeper(address keeper) external override onlyPoolAdmin {
        require(keeper != address(0), Errors.VL_INVALID_INPUT);
        _keeper = keeper;

        emit SetKeeper(keeper);
    }

    /**
     * @notice Burns aTokens and sends underlying tokens to receiver.
     * @dev Only callable by LendingPool to handle state updates.
     */
    function burn(address, address, uint256, uint256) external override onlyLendingPool {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Mints new aTokens to a user.
     * @dev Only callable by LendingPool to handle state updates.
     */
    function mint(address, uint256, uint256) external override onlyLendingPool returns (bool) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Mints tokens to protocol treasury.
     * @dev Only callable by LendingPool.
     */
    function mintToCod3xTreasury(uint256, uint256) external override onlyLendingPool {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Handles aToken transfers during liquidations.
     * @dev Only callable by LendingPool.
     */
    function transferOnLiquidation(address, address, uint256) external override onlyLendingPool {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Gets user balance including accrued interest.
     * @dev Returns principal plus generated interest.
     * @return The total balance.
     */
    function balanceOf(address) public view override(IncentivizedERC20, IERC20) returns (uint256) {
        return 0;
    }

    /**
     * @notice Gets user's scaled balance.
     * @dev Returns stored balance divided by liquidity index at last update.
     * @param user The user address.
     * @return The scaled balance.
     */
    function scaledBalanceOf(address user) external view override returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @notice Gets user's scaled balance and total supply.
     * @dev Returns both individual and global scaled amounts.
     * @param user The user address.
     * @return The user's scaled balance.
     * @return The total scaled supply.
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
     * @notice Gets total token supply including interest.
     * @dev Supply increases as interest accrues to all holders.
     * @return The current total supply.
     */
    function totalSupply() public view override(IncentivizedERC20, IERC20) returns (uint256) {
        return 0;
    }

    /**
     * @notice Gets scaled total supply.
     * @dev Returns sum of all debt divided by index.
     * @return The scaled total supply.
     */
    function scaledTotalSupply() public view virtual override returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @notice Gets treasury address.
     * @dev Returns address receiving protocol fees.
     * @return The treasury address.
     */
    function RESERVE_TREASURY_ADDRESS() public view returns (address) {
        return _treasury;
    }

    /**
     * @notice Gets underlying asset address.
     * @dev Returns CdxUSD token address.
     * @return The underlying asset address.
     */
    function UNDERLYING_ASSET_ADDRESS() public view override returns (address) {
        return _underlyingAsset;
    }

    /**
     * @notice Gets reserve type.
     * @dev Returns boolean flag indicating reserve configuration.
     * @return The reserve type.
     */
    function RESERVE_TYPE() external view returns (bool) {
        return _reserveType;
    }

    /**
     * @notice Gets keeper address.
     * @dev Returns address with maintenance privileges.
     * @return The keeper address.
     */
    function KEEPER_ADDRESS() public view returns (address) {
        return _keeper;
    }

    /**
     * @notice Gets lending pool address.
     * @dev Returns main protocol contract.
     * @return The lending pool contract.
     */
    function POOL() public view returns (ILendingPool) {
        return _pool;
    }

    /**
     * @notice Gets incentives controller.
     * @dev Internal helper for IncentivizedERC20.
     * @return The incentives controller.
     */
    function _getIncentivesController() internal view override returns (IRewarder) {
        return _incentivesController;
    }

    /**
     * @notice Gets incentives controller.
     * @dev External accessor for rewards contract.
     * @return The incentives controller.
     */
    function getIncentivesController() external view override returns (IRewarder) {
        return _getIncentivesController();
    }

    /**
     * @notice Transfers underlying tokens to target.
     * @dev Used by LendingPool for borrows, withdrawals and flash loans.
     * @param target Recipient address.
     * @param amount Amount to transfer.
     * @return The amount transferred.
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
     * @notice Handles token repayment.
     * @dev Processes interest and principal repayment.
     * @param user User executing repayment.
     * @param onBehalfOf User being repaid for.
     * @param amount Amount being repaid.
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
     * @notice EIP-2612 permit function.
     * @dev Not supported in this implementation.
     */
    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) external {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Internal transfer implementation.
     * @dev Not supported in this implementation.
     */
    function _transfer(address, address, uint256) internal override {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Updates incentives controller.
     * @dev Only callable by LendingPool.
     * @param incentivesController New controller address.
     */
    function setIncentivesController(address incentivesController)
        external
        override
        onlyLendingPool
    {
        require(incentivesController != address(0), Errors.R_INVALID_ADDRESS);
        _incentivesController = IRewarder(incentivesController);
    }

    /**
     * @notice Rebalances token holdings.
     * @dev Not supported in this implementation.
     */
    function rebalance() external override onlyLendingPool {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Gets lending pool address.
     * @dev Returns address of main protocol contract.
     * @return The lending pool address.
     */
    function getPool() external view returns (address) {
        return address(_pool);
    }

    /**
     * @notice Gets contract revision number.
     * @dev Used for upgrade management.
     * @return The revision number.
     */
    function getRevision() internal pure virtual override returns (uint256) {
        return ATOKEN_REVISION;
    }

    /// @inheritdoc ICdxUsdAToken
    function getVariableDebtToken() external view override returns (address) {
        return address(_cdxUsdVariableDebtToken);
    }

    /// @inheritdoc ICdxUSDFacilitators
    function distributeFeesToTreasury() external virtual override onlyKeeper {
        require(_treasury != address(0), Errors.AT_TREASURY_NOT_SET);
        uint256 balance = IERC20(_underlyingAsset).balanceOf(address(this));

        _reliquaryCdxusdRewarder.fund(_reliquaryAllocation * balance / BPS);

        IERC20(_underlyingAsset).transfer(
            _treasury, IERC20(_underlyingAsset).balanceOf(address(this))
        );
        emit FeesDistributedToTreasury(_treasury, _underlyingAsset, balance);
    }

    /// --------- Share logic ---------
    /**
     * @notice Transfers shares between accounts.
     * @dev Not supported in this implementation.
     */
    function transferShare(address from, address to, uint256 shareAmount) external {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Approves share spending.
     * @dev Not supported in this implementation.
     */
    function shareApprove(address owner, address spender, uint256 shareAmount) external {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Gets approved share amount.
     * @dev Not supported in this implementation.
     */
    function shareAllowances(address owner, address spender) external view returns (uint256) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Converts asset amount to shares.
     * @dev Not supported in this implementation.
     */
    function convertToShares(uint256 assetAmount) external view returns (uint256) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Converts shares to asset amount.
     * @dev Not supported in this implementation.
     */
    function convertToAssets(uint256 shareAmount) external view returns (uint256) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Gets wrapper address.
     * @dev Returns self since no wrapper exists.
     * @return The aToken address.
     */
    function WRAPPER_ADDRESS() external view returns (address) {
        return address(this);
    }

    /// --------- Rehypothecation logic ---------

    /**
     * @notice Updates treasury address.
     * @dev Only callable by LendingPool.
     * @param newTreasury New treasury address.
     */
    function setTreasury(address newTreasury) external override onlyLendingPool {
        require(newTreasury != address(0), Errors.AT_INVALID_ADDRESS);
        _treasury = newTreasury;

        emit TreasurySet(newTreasury);
    }

    /// overrides
    /**
     * @notice Gets total managed assets.
     * @dev Not supported in this implementation.
     */
    function getTotalManagedAssets() external view override returns (uint256) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Sets farming percentage.
     * @dev Not supported in this implementation.
     */
    function setFarmingPct(uint256) external override {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Sets claiming threshold.
     * @dev Not supported in this implementation.
     */
    function setClaimingThreshold(uint256) external override {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Sets farming percentage drift.
     * @dev Not supported in this implementation.
     */
    function setFarmingPctDrift(uint256) external override {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Sets profit handler.
     * @dev Not supported in this implementation.
     */
    function setProfitHandler(address) external override {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @notice Sets vault address.
     * @dev Not supported in this implementation.
     */
    function setVault(address) external override {
        revert("OPERATION_NOT_SUPPORTED");
    }
}
