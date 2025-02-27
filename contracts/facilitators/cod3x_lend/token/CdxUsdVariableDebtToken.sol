// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.22;

// import {IVariableDebtToken} from "lib/Cod3x-Lend/contracts/interfaces/IVariableDebtToken.sol";
// import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";
// import {SafeCast} from "lib/Cod3x-Lend/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
// import {Errors} from "lib/Cod3x-Lend/contracts/protocol/libraries/helpers/Errors.sol";
// import {DebtTokenBase} from
//     "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC20/base/DebtTokenBase.sol";
// import {ILendingPool} from "lib/Cod3x-Lend/contracts/interfaces/ILendingPool.sol";
// import {IRewarder} from "lib/Cod3x-Lend/contracts/interfaces/IRewarder.sol";

// /**
//  * @title CdxUsdVariableDebtToken
//  * @notice Implements a variable debt token to track the borrowing positions of users
//  * at variable rate mode
//  * @author Cod3x - Beirao
//  */
// contract CdxUsdVariableDebtToken is DebtTokenBase, IVariableDebtToken {
//     using WadRayMath for uint256;
//     using SafeCast for uint256;

//     uint256 public constant DEBT_TOKEN_REVISION = 0x1;

//     address internal _cdxUsdAToken;
//     ILendingPool internal _pool;
//     address internal _underlyingAsset;
//     bool internal _reserveType;
//     IRewarder internal _incentivesController;

//     mapping(address => CdxUsdUserState) internal _userState;

//     struct CdxUsdUserState {
//         uint128 accumulatedDebtInterest; // Accumulated debt interest of the user.
//         uint128 previousIndex; // Previous index of the user.
//     }

//     /// Events
//     event Mint(
//         address indexed caller,
//         address indexed onBehalfOf,
//         uint256 value,
//         uint256 balanceIncrease,
//         uint256 index
//     );
//     event Burn(
//         address indexed from,
//         address indexed target,
//         uint256 value,
//         uint256 balanceIncrease,
//         uint256 index
//     );

//     modifier onlyAToken() {
//         require(_msgSender() == _cdxUsdAToken, "CALLER_NOT_A_TOKEN");
//         _;
//     }

//     modifier onlyPoolAdmin() {
//         require(
//             _msgSender() == _pool.getAddressesProvider().getPoolAdmin(),
//             Errors.CALLER_NOT_POOL_ADMIN
//         );
//         _;
//     }

//     /**
//      * @dev Initializes the debt token. MUST also call setAToken() at initialization.
//      * @param pool The address of the lending pool where this aToken will be used
//      * @param underlyingAsset The address of the underlying asset of this aToken (E.g. WETH for aWETH)
//      * @param incentivesController The smart contract managing potential incentives distribution
//      * @param debtTokenDecimals The decimals of the debtToken, same as the underlying asset's
//      * @param debtTokenName The name of the token
//      * @param debtTokenSymbol The symbol of the token
//      */
//     function initialize(
//         ILendingPool pool,
//         address underlyingAsset,
//         IRewarder incentivesController,
//         uint8 debtTokenDecimals,
//         bool,
//         string memory debtTokenName,
//         string memory debtTokenSymbol,
//         bytes calldata params
//     ) public override initializer {
//         _setName(debtTokenName);
//         _setSymbol(debtTokenSymbol);
//         _setDecimals(debtTokenDecimals);

//         _pool = pool;
//         _underlyingAsset = underlyingAsset;
//         _incentivesController = incentivesController;

//         _reserveType = true; // @issue always false? cdxUSD can't rehypothecate.

//         emit Initialized(
//             underlyingAsset,
//             address(pool),
//             address(incentivesController),
//             debtTokenDecimals,
//             _reserveType,
//             debtTokenName,
//             debtTokenSymbol,
//             params
//         );
//     }

//     function setAToken(address cdxUsdAToken) external onlyPoolAdmin {
//         require(_cdxUsdAToken == address(0), "ATOKEN_ALREADY_SET");
//         require(cdxUsdAToken != address(0), "ZERO_ADDRESS_NOT_VALID");
//         _cdxUsdAToken = cdxUsdAToken;
//     }

//     /**
//      * @dev Gets the revision of the variable debt token implementation
//      * @return The debt token implementation revision
//      *
//      */
//     function getRevision() internal pure virtual override returns (uint256) {
//         return DEBT_TOKEN_REVISION;
//     }

//     /**
//      * @dev Calculates the accumulated debt balance of the user
//      * @return The debt balance of the user
//      *
//      */
//     function balanceOf(address user) public view virtual override returns (uint256) {
//         uint256 scaledBalance = super.balanceOf(user);

//         if (scaledBalance == 0) {
//             return 0;
//         }

//         return scaledBalance.rayMul(
//             _pool.getReserveNormalizedVariableDebt(_underlyingAsset, _reserveType)
//         );
//     }

//     /**
//      * @dev Mints debt token to the `onBehalfOf` address
//      * -  Only callable by the LendingPool
//      * @param user The address receiving the borrowed underlying, being the delegatee in case
//      * of credit delegate, or same as `onBehalfOf` otherwise
//      * @param onBehalfOf The address receiving the debt tokens
//      * @param amount The amount of debt being minted
//      * @param index The variable debt index of the reserve
//      * @return `true` if the the previous balance of the user is 0
//      */
//     function mint(address user, address onBehalfOf, uint256 amount, uint256 index)
//         external
//         override
//         onlyLendingPool
//         returns (bool)
//     {
//         if (user != onBehalfOf) {
//             _decreaseBorrowAllowance(onBehalfOf, user, amount);
//         }

//         uint256 previousScaledBalance = super.balanceOf(onBehalfOf);
//         uint256 amountScaled = amount.rayDiv(index);
//         require(amountScaled != 0, Errors.CT_INVALID_MINT_AMOUNT);

//         uint256 balanceIncrease = _accrueDebtOnAction(onBehalfOf, previousScaledBalance, index);

//         _mint(onBehalfOf, amountScaled);

//         uint256 amountToMint = amount + balanceIncrease;
//         emit Transfer(address(0), onBehalfOf, amountToMint);
//         emit Mint(user, onBehalfOf, amountToMint, balanceIncrease, index);

//         return previousScaledBalance == 0;
//     }

//     /**
//      * @dev Burns user variable debt
//      * - Only callable by the LendingPool
//      * @param user The user whose debt is getting burned
//      * @param amount The amount getting burned
//      * @param index The variable debt index of the reserve
//      */
//     function burn(address user, uint256 amount, uint256 index) external override onlyLendingPool {
//         uint256 amountScaled = amount.rayDiv(index);
//         require(amountScaled != 0, Errors.CT_INVALID_BURN_AMOUNT);

//         uint256 balanceBeforeBurn = balanceOf(user);

//         uint256 previousScaledBalance = super.balanceOf(user);
//         uint256 balanceIncrease = _accrueDebtOnAction(user, previousScaledBalance, index);

//         _burn(user, amountScaled);

//         if (balanceIncrease > amount) {
//             uint256 amountToMint = balanceIncrease - amount;
//             emit Transfer(address(0), user, amountToMint);
//             emit Mint(user, user, amountToMint, balanceIncrease, index);
//         } else {
//             uint256 amountToBurn = amount - balanceIncrease;
//             emit Transfer(user, address(0), amountToBurn);
//             emit Burn(user, user, amountToBurn, balanceIncrease, index);
//         }
//     }

//     /**
//      * @dev Decrease the amount of interests accumulated by the user
//      * @param user The address of the user
//      * @param amount The value to be decrease
//      */
//     function decreaseBalanceFromInterest(address user, uint256 amount) external onlyAToken {
//         _userState[user].accumulatedDebtInterest =
//             (_userState[user].accumulatedDebtInterest - amount).toUint128();
//     }

//     /**
//      * @dev Returns the amount of interests accumulated by the user
//      * @param user The address of the user
//      * @return The amount of interests accumulated by the user
//      */
//     function getBalanceFromInterest(address user) external view returns (uint256) {
//         return _userState[user].accumulatedDebtInterest;
//     }

//     /**
//      * @dev Returns the principal debt balance of the user from
//      * @return The debt balance of the user since the last burn/mint action
//      */
//     function scaledBalanceOf(address user) public view virtual override returns (uint256) {
//         return super.balanceOf(user);
//     }

//     /**
//      * @dev Returns the total supply of the variable debt token. Represents the total debt accrued by the users
//      * @return The total supply
//      */
//     function totalSupply() public view virtual override returns (uint256) {
//         return super.totalSupply().rayMul(
//             _pool.getReserveNormalizedVariableDebt(_underlyingAsset, _reserveType)
//         );
//     }

//     /**
//      * @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
//      * @return the scaled total supply
//      */
//     function scaledTotalSupply() public view virtual override returns (uint256) {
//         return super.totalSupply();
//     }

//     /**
//      * @dev Returns the principal balance of the user and principal total supply.
//      * @param user The address of the user
//      * @return The principal balance of the user
//      * @return The principal total supply
//      */
//     function getScaledUserBalanceAndSupply(address user)
//         external
//         view
//         override
//         returns (uint256, uint256)
//     {
//         return (super.balanceOf(user), super.totalSupply());
//     }

//     /**
//      * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
//      */
//     function UNDERLYING_ASSET_ADDRESS() public view returns (address) {
//         return _underlyingAsset;
//     }

//     /**
//      * @dev Returns the address of the incentives controller contract
//      */
//     function getIncentivesController() external view override returns (IRewarder) {
//         return _getIncentivesController();
//     }

//     /**
//      * @dev Returns the address of the lending pool where this aToken is used
//      */
//     function POOL() public view returns (ILendingPool) {
//         return _pool;
//     }

//     function _getIncentivesController() internal view override returns (IRewarder) {
//         return _incentivesController;
//     }

//     function _getUnderlyingAssetAddress() internal view override returns (address) {
//         return _underlyingAsset;
//     }

//     function _getLendingPool() internal view override returns (ILendingPool) {
//         return _pool;
//     }

//     function setIncentivesController(address newController) external onlyLendingPool {
//         require(newController != address(0), "INVALID_CONTROLLER");
//         _incentivesController = IRewarder(newController);
//     }

//     function getAToken() external view returns (address) {
//         return _cdxUsdAToken;
//     }

//     /**
//      * @dev Accumulates debt of the user since last action.
//      * @param user The address of the user
//      * @param previousScaledBalance The previous scaled balance of the user
//      * @param index The variable debt index of the reserve
//      * @return The increase in scaled balance since the last action of `user`
//      */
//     function _accrueDebtOnAction(address user, uint256 previousScaledBalance, uint256 index)
//         internal
//         returns (uint256)
//     {
//         uint256 balanceIncrease = previousScaledBalance.rayMul(index)
//             - previousScaledBalance.rayMul(_userState[user].previousIndex);

//         _userState[user].previousIndex = index.toUint128();

//         _userState[user].accumulatedDebtInterest =
//             (balanceIncrease + _userState[user].accumulatedDebtInterest).toUint128();

//         return balanceIncrease;
//     }
// }
