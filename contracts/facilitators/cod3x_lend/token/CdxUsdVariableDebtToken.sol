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
 * @notice Implements a variable debt token to track the borrowing positions of users
 * at variable rate mode
 * @author Cod3x - Beirao
 */
contract CdxUsdVariableDebtToken is
    IncentivizedERC20("DEBTTOKEN_IMPL", "DEBTTOKEN_IMPL", 0),
    VersionedInitializable,
    IVariableDebtToken
{
    using WadRayMath for uint256;
    using SafeCast for uint256;

    /// @dev Revision number of the contract implementation
    uint256 public constant DEBT_TOKEN_REVISION = 0x1;

    /// @dev Reference to the CdxUsdAToken contract
    address internal _cdxUsdAToken;

    /// @dev Reference to the lending pool contract
    ILendingPool internal _pool;

    /// @dev The address of the underlying asset
    address internal _underlyingAsset;

    /// @dev Flag indicating the reserve type
    bool internal _reserveType;

    /// @dev Reference to the incentives controller contract
    IRewarder internal _incentivesController;

    /// @dev Mapping of user addresses to their debt state
    mapping(address => CdxUsdUserState) internal _userState;

    /// @dev Mapping of delegator addresses to delegatee addresses to borrow allowances
    mapping(address => mapping(address => uint256)) internal _borrowAllowances;

    /// @dev Structure to track user's debt state
    struct CdxUsdUserState {
        uint128 accumulatedDebtInterest; // Accumulated debt interest of the user.
        uint128 previousIndex; // Previous index of the user.
    }

    /**
     * @dev Emitted when debt tokens are minted
     * @param caller The address performing the mint
     * @param onBehalfOf The address of the user that will receive the minted tokens
     * @param value The amount of tokens minted
     * @param balanceIncrease The increase in balance since the last action of the user
     * @param index The current debt index of the reserve
     */
    event Mint(
        address indexed caller,
        address indexed onBehalfOf,
        uint256 value,
        uint256 balanceIncrease,
        uint256 index
    );

    /**
     * @dev Emitted when debt tokens are burned
     * @param from The address whose tokens are being burned
     * @param target The address that will receive the underlying, if any
     * @param value The amount being burned
     * @param balanceIncrease The increase in balance since the last action of the user
     * @param index The current debt index of the reserve
     */
    event Burn(
        address indexed from,
        address indexed target,
        uint256 value,
        uint256 balanceIncrease,
        uint256 index
    );

    /// @dev Ensures the caller is the AToken
    modifier onlyAToken() {
        require(msg.sender == _cdxUsdAToken, "CALLER_NOT_A_TOKEN");
        _;
    }

    /// @dev Ensures the caller is the pool admin
    modifier onlyPoolAdmin() {
        require(
            msg.sender == _pool.getAddressesProvider().getPoolAdmin(),
            Errors.VL_CALLER_NOT_POOL_ADMIN
        );
        _;
    }

    /// @dev Only lending pool can call functions marked by this modifier
    modifier onlyLendingPool() {
        require(msg.sender == address(_getLendingPool()), Errors.AT_CALLER_MUST_BE_LENDING_POOL);
        _;
    }

    constructor() {
        _blockInitializing();
    }

    /**
     * @dev Initializes the debt token. MUST also call setAToken() at initialization.
     * @param pool The address of the lending pool where this aToken will be used
     * @param underlyingAsset The address of the underlying asset of this aToken (E.g. WETH for aWETH)
     * @param incentivesController The smart contract managing potential incentives distribution
     * @param debtTokenDecimals The decimals of the debtToken, same as the underlying asset's
     * @param debtTokenName The name of the token
     * @param debtTokenSymbol The symbol of the token
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
     * @dev Sets the associated AToken address
     * @param cdxUsdAToken The address of the CdxUsdAToken
     */
    function setAToken(address cdxUsdAToken) external onlyPoolAdmin {
        require(_cdxUsdAToken == address(0), "ATOKEN_ALREADY_SET");
        require(cdxUsdAToken != address(0), "ZERO_ADDRESS_NOT_VALID");
        _cdxUsdAToken = cdxUsdAToken;
    }

    /**
     * @dev Gets the revision of the variable debt token implementation
     * @return The debt token implementation revision
     *
     */
    function getRevision() internal pure virtual override returns (uint256) {
        return DEBT_TOKEN_REVISION;
    }

    /**
     * @dev Calculates the accumulated debt balance of the user
     * @return The debt balance of the user
     *
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
     * @dev Mints debt token to the `onBehalfOf` address
     * -  Only callable by the LendingPool
     * @param user The address receiving the borrowed underlying, being the delegatee in case
     * of credit delegate, or same as `onBehalfOf` otherwise
     * @param onBehalfOf The address receiving the debt tokens
     * @param amount The amount of debt being minted
     * @param index The variable debt index of the reserve
     * @return `true` if the the previous balance of the user is 0
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
     * @dev Burns user variable debt
     * - Only callable by the LendingPool
     * @param user The user whose debt is getting burned
     * @param amount The amount getting burned
     * @param index The variable debt index of the reserve
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
     * @dev delegates borrowing power to a user on the specific debt token
     * @param delegatee the address receiving the delegated borrowing power
     * @param amount the maximum amount being delegated. Delegation will still
     * respect the liquidation constraints (even if delegated, a delegatee cannot
     * force a delegator HF to go below 1)
     */
    function approveDelegation(address delegatee, uint256 amount) external override {
        _borrowAllowances[msg.sender][delegatee] = amount;
        emit BorrowAllowanceDelegated(msg.sender, delegatee, _getUnderlyingAssetAddress(), amount);
    }

    /**
     * @dev returns the borrow allowance of the user
     * @param fromUser The user to giving allowance
     * @param toUser The user to give allowance to
     * @return the current allowance of toUser
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
     * @dev Decrease the amount of interests accumulated by the user
     * @param user The address of the user
     * @param amount The value to be decrease
     */
    function decreaseBalanceFromInterest(address user, uint256 amount) external onlyAToken {
        _userState[user].accumulatedDebtInterest =
            (_userState[user].accumulatedDebtInterest - amount).toUint128();
    }

    /**
     * @dev Returns the amount of interests accumulated by the user
     * @param user The address of the user
     * @return The amount of interests accumulated by the user
     */
    function getBalanceFromInterest(address user) external view returns (uint256) {
        return _userState[user].accumulatedDebtInterest;
    }

    /**
     * @dev Returns the principal debt balance of the user from
     * @return The debt balance of the user since the last burn/mint action
     */
    function scaledBalanceOf(address user) public view virtual override returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @dev Returns the total supply of the variable debt token. Represents the total debt accrued by the users
     * @return The total supply
     */
    function totalSupply() public view virtual override returns (uint256) {
        return super.totalSupply().rayMul(
            _pool.getReserveNormalizedVariableDebt(_underlyingAsset, _reserveType)
        );
    }

    /**
     * @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
     * @return the scaled total supply
     */
    function scaledTotalSupply() public view virtual override returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @dev Returns the principal balance of the user and principal total supply.
     * @param user The address of the user
     * @return The principal balance of the user
     * @return The principal total supply
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
     * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     * @return The address of the underlying asset
     */
    function UNDERLYING_ASSET_ADDRESS() public view returns (address) {
        return _underlyingAsset;
    }

    /**
     * @dev Returns the address of the incentives controller contract
     * @return The address of the incentives controller
     */
    function getIncentivesController() external view override returns (IRewarder) {
        return _getIncentivesController();
    }

    /**
     * @dev Internal function to get the underlying asset address.
     * @return The address of the underlying asset.
     */
    function _getUnderlyingAssetAddress() internal view returns (address) {
        return _underlyingAsset;
    }

    /**
     * @dev Internal function to get the lending pool.
     * @return The lending pool interface.
     */
    function _getLendingPool() internal view returns (ILendingPool) {
        return _pool;
    }

    /**
     * @dev Returns the address of the lending pool where this aToken is used
     * @return The address of the lending pool
     */
    function POOL() public view returns (ILendingPool) {
        return _pool;
    }

    /**
     * @dev Internal function to get the incentives controller
     * @return The incentives controller interface
     */
    function _getIncentivesController() internal view override returns (IRewarder) {
        return _incentivesController;
    }

    /**
     * @dev Sets a new incentives controller
     * @param newController The address of the new incentives controller
     */
    function setIncentivesController(address newController) external onlyLendingPool {
        require(newController != address(0), "INVALID_CONTROLLER");
        _incentivesController = IRewarder(newController);
    }

    /**
     * @dev Returns the address of the associated AToken
     * @return The address of the AToken
     */
    function getAToken() external view returns (address) {
        return _cdxUsdAToken;
    }

    /**
     * @dev Being non transferrable, the debt token does not implement any of the
     * standard ERC20 functions for transfer and allowance.
     */
    function transfer(address, uint256) public virtual override returns (bool) {
        revert("TRANSFER_NOT_SUPPORTED");
    }

    /**
     * @dev Being non transferrable, the debt token does not implement any of the
     * standard ERC20 functions for transfer and allowance.
     */
    function allowance(address, address) public view virtual override returns (uint256) {
        revert("ALLOWANCE_NOT_SUPPORTED");
    }

    /**
     * @dev Being non transferrable, the debt token does not implement any of the
     * standard ERC20 functions for transfer and allowance.
     */
    function approve(address, uint256) public virtual override returns (bool) {
        revert("APPROVAL_NOT_SUPPORTED");
    }

    /**
     * @dev Being non transferrable, the debt token does not implement any of the
     * standard ERC20 functions for transfer and allowance.
     */
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert("TRANSFER_NOT_SUPPORTED");
    }

    /**
     * @dev Being non transferrable, the debt token does not implement any of the
     * standard ERC20 functions for transfer and allowance.
     */
    function increaseAllowance(address, uint256) public virtual override returns (bool) {
        revert("ALLOWANCE_NOT_SUPPORTED");
    }

    /**
     * @dev Being non transferrable, the debt token does not implement any of the
     * standard ERC20 functions for transfer and allowance.
     */
    function decreaseAllowance(address, uint256) public virtual override returns (bool) {
        revert("ALLOWANCE_NOT_SUPPORTED");
    }

    /**
     * @dev Accumulates debt of the user since last action.
     * @param user The address of the user
     * @param previousScaledBalance The previous scaled balance of the user
     * @param index The variable debt index of the reserve
     * @return The increase in scaled balance since the last action of `user`
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
     * @dev Decreases the borrow allowance of a user
     * @param delegator The address of the delegator
     * @param delegatee The address of the delegatee
     * @param amount The amount to decrease the allowance by
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
