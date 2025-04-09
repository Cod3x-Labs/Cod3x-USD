// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {IVariableDebtToken} from "lib/Cod3x-Lend/contracts/interfaces/IVariableDebtToken.sol";
import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";
import {SafeCast} from "lib/Cod3x-Lend/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Errors} from "lib/Cod3x-Lend/contracts/protocol/libraries/helpers/Errors.sol";
import {ILendingPool} from "lib/Cod3x-Lend/contracts/interfaces/ILendingPool.sol";
import {IRewarder} from "lib/Cod3x-Lend/contracts/interfaces/IRewarder.sol";
import {VersionedInitializable} from
    "lib/Cod3x-Lend/contracts/protocol/libraries/upgradeability/VersionedInitializable.sol";
import {IncentivizedERC20} from
    "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC20/IncentivizedERC20.sol";

/**
 * @title CdxUsdVariableDebtToken
 * @notice A variable debt token that tracks user borrowing positions with variable interest rates.
 * The token represents debt owed by users who have borrowed from the lending pool. The debt amount
 * fluctuates based on the variable interest rate applied.
 * @author Cod3x - Beirao
 */
contract CdxUsdVariableDebtToken is
    IncentivizedERC20("DEBTTOKEN_IMPL", "DEBTTOKEN_IMPL", 0),
    VersionedInitializable,
    IVariableDebtToken
{
    using WadRayMath for uint256;
    using SafeCast for uint256;

    /// @dev Revision number used for version control. Set to 0x1 for initial implementation.
    uint256 public constant DEBT_TOKEN_REVISION = 0x1;

    /// @dev Address of the associated CdxUsdAToken contract that handles deposits.
    address internal _cdxUsdAToken;

    /// @dev Reference to the lending pool contract that manages lending/borrowing operations.
    ILendingPool internal _pool;

    /// @dev Address of the underlying asset that can be borrowed through this debt token.
    address internal _underlyingAsset;

    /// @dev Flag to differentiate between reserve configurations. Used for reserve management.
    bool internal _reserveType;

    /// @dev Contract that manages distribution of incentive rewards to token holders.
    IRewarder internal _incentivesController;

    /// @dev Maps user addresses to their debt state, tracking individual borrowing positions.
    mapping(address => CdxUsdUserState) internal _userState;

    /// @dev Maps delegators to delegatees with their approved borrowing allowances.
    mapping(address => mapping(address => uint256)) internal _borrowAllowances;

    /// @dev Struct containing user debt state variables.
    struct CdxUsdUserState {
        uint128 accumulatedDebtInterest; // Total interest accrued on user's debt.
        uint128 previousIndex; // Last recorded debt index for the user.
    }

    /**
     * @dev Emitted when new debt tokens are minted.
     * @param caller The address initiating the mint operation.
     * @param onBehalfOf The address that will own the minted tokens.
     * @param value The amount of tokens being minted.
     * @param balanceIncrease The increase in balance since user's last action.
     * @param index The current debt index of the reserve.
     */
    event Mint(
        address indexed caller,
        address indexed onBehalfOf,
        uint256 value,
        uint256 balanceIncrease,
        uint256 index
    );

    /**
     * @dev Emitted when debt tokens are burned.
     * @param from The address whose tokens are being burned.
     * @param target The address receiving underlying assets, if applicable.
     * @param value The amount of tokens being burned.
     * @param balanceIncrease The increase in balance since user's last action.
     * @param index The current debt index of the reserve.
     */
    event Burn(
        address indexed from,
        address indexed target,
        uint256 value,
        uint256 balanceIncrease,
        uint256 index
    );

    /// @dev Ensures only the AToken contract can call the modified function.
    modifier onlyAToken() {
        require(msg.sender == _cdxUsdAToken, Errors.AT_CALLER_NOT_ATOKEN);
        _;
    }

    /// @dev Ensures only the pool admin can call the modified function.
    modifier onlyPoolAdmin() {
        require(
            msg.sender == _pool.getAddressesProvider().getPoolAdmin(),
            Errors.VL_CALLER_NOT_POOL_ADMIN
        );
        _;
    }

    /// @dev Ensures only the lending pool contract can call the modified function.
    modifier onlyLendingPool() {
        require(msg.sender == address(_getLendingPool()), Errors.AT_CALLER_MUST_BE_LENDING_POOL);
        _;
    }

    constructor() {
        _blockInitializing();
    }

    /**
     * @dev Sets up the debt token with initial parameters. Must call setAToken() after initialization.
     * @param pool The lending pool contract address.
     * @param underlyingAsset The underlying asset address (e.g. WETH for aWETH).
     * @param incentivesController The contract managing incentives distribution.
     * @param debtTokenDecimals The number of decimals for the debt token.
     * @param debtTokenName The name of the debt token.
     * @param debtTokenSymbol The symbol of the debt token.
     */
    function initialize(
        ILendingPool pool,
        address underlyingAsset,
        IRewarder incentivesController,
        uint8 debtTokenDecimals,
        bool,
        string memory debtTokenName,
        string memory debtTokenSymbol,
        bytes calldata params
    ) public override initializer {
        _setName(debtTokenName);
        _setSymbol(debtTokenSymbol);
        _setDecimals(debtTokenDecimals);

        _pool = pool;
        _underlyingAsset = underlyingAsset;
        _incentivesController = incentivesController;

        _reserveType = false;

        emit Initialized(
            underlyingAsset,
            address(pool),
            address(incentivesController),
            debtTokenDecimals,
            _reserveType,
            debtTokenName,
            debtTokenSymbol,
            params
        );
    }

    /**
     * @dev Links this debt token to its corresponding AToken contract.
     * @param cdxUsdAToken The address of the CdxUsdAToken to link.
     */
    function setAToken(address cdxUsdAToken) external onlyPoolAdmin {
        require(_cdxUsdAToken == address(0), Errors.AT_ATOKEN_ALREADY_SET);
        require(cdxUsdAToken != address(0), Errors.AT_INVALID_ADDRESS);
        _cdxUsdAToken = cdxUsdAToken;
    }

    /**
     * @dev Returns the current revision number of the contract implementation.
     * @return The debt token implementation revision number.
     */
    function getRevision() internal pure virtual override returns (uint256) {
        return DEBT_TOKEN_REVISION;
    }

    /**
     * @dev Calculates the current debt balance of a user including accrued interest.
     * @return The total debt balance including interest.
     */
    function balanceOf(address user) public view virtual override returns (uint256) {
        uint256 scaledBalance = super.balanceOf(user);

        if (scaledBalance == 0) {
            return 0;
        }

        return scaledBalance.rayMul(
            _pool.getReserveNormalizedVariableDebt(_underlyingAsset, _reserveType)
        );
    }

    /**
     * @dev Creates new debt tokens for a user. Only callable by the LendingPool.
     * @param user The address receiving borrowed assets (delegatee or same as onBehalfOf).
     * @param onBehalfOf The address that will own the debt tokens.
     * @param amount The amount of debt being created.
     * @param index The variable debt index of the reserve.
     * @return True if this is the user's first debt position.
     */
    function mint(address user, address onBehalfOf, uint256 amount, uint256 index)
        external
        override
        onlyLendingPool
        returns (bool)
    {
        if (user != onBehalfOf) {
            _decreaseBorrowAllowance(onBehalfOf, user, amount);
        }

        uint256 previousScaledBalance = super.balanceOf(onBehalfOf);
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, Errors.AT_INVALID_MINT_AMOUNT);

        uint256 balanceIncrease = _accrueDebtOnAction(onBehalfOf, previousScaledBalance, index);

        _mint(onBehalfOf, amountScaled);

        uint256 amountToMint = amount + balanceIncrease;
        emit Transfer(address(0), onBehalfOf, amountToMint);
        emit Mint(user, onBehalfOf, amountToMint, balanceIncrease, index);

        return previousScaledBalance == 0;
    }

    /**
     * @dev Destroys debt tokens when debt is repaid. Only callable by the LendingPool.
     * @param user The user whose debt is being burned.
     * @param amount The amount of debt being burned.
     * @param index The variable debt index of the reserve.
     */
    function burn(address user, uint256 amount, uint256 index) external override onlyLendingPool {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, Errors.AT_INVALID_BURN_AMOUNT);

        uint256 balanceBeforeBurn = balanceOf(user);

        uint256 previousScaledBalance = super.balanceOf(user);
        uint256 balanceIncrease = _accrueDebtOnAction(user, previousScaledBalance, index);

        _burn(user, amountScaled);

        if (balanceIncrease > amount) {
            uint256 amountToMint = balanceIncrease - amount;
            emit Transfer(address(0), user, amountToMint);
            emit Mint(user, user, amountToMint, balanceIncrease, index);
        } else {
            uint256 amountToBurn = amount - balanceIncrease;
            emit Transfer(user, address(0), amountToBurn);
            emit Burn(user, user, amountToBurn, balanceIncrease, index);
        }
    }

    /**
     * @dev Allows a user to delegate borrowing power to another address.
     * @param delegatee The address receiving borrowing power.
     * @param amount The maximum amount that can be borrowed by the delegatee.
     */
    function approveDelegation(address delegatee, uint256 amount) external override {
        _borrowAllowances[msg.sender][delegatee] = amount;
        emit BorrowAllowanceDelegated(msg.sender, delegatee, _getUnderlyingAssetAddress(), amount);
    }

    /**
     * @dev Returns the current borrow allowance from one user to another.
     * @param fromUser The user delegating borrowing power.
     * @param toUser The user receiving borrowing power.
     * @return The current borrowing allowance.
     */
    function borrowAllowance(address fromUser, address toUser)
        external
        view
        override
        returns (uint256)
    {
        return _borrowAllowances[fromUser][toUser];
    }

    /**
     * @dev Reduces a user's accumulated interest by a specified amount.
     * @param user The address of the user.
     * @param amount The amount to decrease.
     */
    function decreaseBalanceFromInterest(address user, uint256 amount) external onlyAToken {
        _userState[user].accumulatedDebtInterest =
            (_userState[user].accumulatedDebtInterest - amount).toUint128();
    }

    /**
     * @dev Returns the total interest accumulated by a user.
     * @param user The address of the user.
     * @return The total accumulated interest.
     */
    function getBalanceFromInterest(address user) external view returns (uint256) {
        return _userState[user].accumulatedDebtInterest;
    }

    /**
     * @dev Returns the user's debt balance excluding interest since last action.
     * @return The principal debt balance.
     */
    function scaledBalanceOf(address user) public view virtual override returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @dev Returns the total debt including all accrued interest.
     * @return The total debt supply.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return super.totalSupply().rayMul(
            _pool.getReserveNormalizedVariableDebt(_underlyingAsset, _reserveType)
        );
    }

    /**
     * @dev Returns the total debt excluding interest since last action.
     * @return The scaled total supply.
     */
    function scaledTotalSupply() public view virtual override returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @dev Returns a user's principal balance and total principal supply.
     * @param user The address of the user.
     * @return The user's principal balance and total principal supply.
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
     * @dev Returns the address of the underlying asset.
     * @return The underlying asset address.
     */
    function UNDERLYING_ASSET_ADDRESS() public view returns (address) {
        return _underlyingAsset;
    }

    /**
     * @dev Returns the address of the incentives controller.
     * @return The incentives controller address.
     */
    function getIncentivesController() external view override returns (IRewarder) {
        return _getIncentivesController();
    }

    /**
     * @dev Internal function to get the underlying asset address.
     * @return The underlying asset address.
     */
    function _getUnderlyingAssetAddress() internal view returns (address) {
        return _underlyingAsset;
    }

    /**
     * @dev Internal function to get the lending pool interface.
     * @return The lending pool interface.
     */
    function _getLendingPool() internal view returns (ILendingPool) {
        return _pool;
    }

    /**
     * @dev Returns the address of the lending pool.
     * @return The lending pool address.
     */
    function POOL() public view returns (ILendingPool) {
        return _pool;
    }

    /**
     * @dev Internal function to get the incentives controller interface.
     * @return The incentives controller interface.
     */
    function _getIncentivesController() internal view override returns (IRewarder) {
        return _incentivesController;
    }

    /**
     * @dev Updates the incentives controller address.
     * @param newController The address of the new controller.
     */
    function setIncentivesController(address newController) external onlyLendingPool {
        require(newController != address(0), Errors.AT_INVALID_CONTROLLER);
        _incentivesController = IRewarder(newController);
    }

    /**
     * @dev Returns the address of the associated AToken.
     * @return The AToken address.
     */
    function getAToken() external view returns (address) {
        return _cdxUsdAToken;
    }

    /**
     * @dev Debt tokens are non-transferrable. This function always reverts.
     */
    function transfer(address, uint256) public virtual override returns (bool) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @dev Debt tokens are non-transferrable. This function always reverts.
     */
    function allowance(address, address) public view virtual override returns (uint256) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @dev Debt tokens are non-transferrable. This function always reverts.
     */
    function approve(address, uint256) public virtual override returns (bool) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @dev Debt tokens are non-transferrable. This function always reverts.
     */
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @dev Debt tokens are non-transferrable. This function always reverts.
     */
    function increaseAllowance(address, uint256) public virtual override returns (bool) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @dev Debt tokens are non-transferrable. This function always reverts.
     */
    function decreaseAllowance(address, uint256) public virtual override returns (bool) {
        revert("OPERATION_NOT_SUPPORTED");
    }

    /**
     * @dev Updates user's debt state and calculates interest accrued since last action.
     * @param user The address of the user.
     * @param previousScaledBalance The user's previous scaled balance.
     * @param index The current debt index.
     * @return The increase in balance since last action.
     */
    function _accrueDebtOnAction(address user, uint256 previousScaledBalance, uint256 index)
        internal
        returns (uint256)
    {
        uint256 balanceIncrease = previousScaledBalance.rayMul(index)
            - previousScaledBalance.rayMul(_userState[user].previousIndex);

        _userState[user].previousIndex = index.toUint128();

        _userState[user].accumulatedDebtInterest =
            (balanceIncrease + _userState[user].accumulatedDebtInterest).toUint128();

        return balanceIncrease;
    }

    /**
     * @dev Reduces the borrowing allowance granted to a delegatee.
     * @param delegator The address that granted the allowance.
     * @param delegatee The address that received the allowance.
     * @param amount The amount to decrease the allowance by.
     */
    function _decreaseBorrowAllowance(address delegator, address delegatee, uint256 amount)
        internal
    {
        uint256 oldAllowance = _borrowAllowances[delegator][delegatee];
        require(oldAllowance >= amount, Errors.AT_BORROW_ALLOWANCE_NOT_ENOUGH);
        uint256 newAllowance = oldAllowance - amount;

        _borrowAllowances[delegator][delegatee] = newAllowance;

        emit BorrowAllowanceDelegated(
            delegator, delegatee, _getUnderlyingAssetAddress(), newAllowance
        );
    }
}
