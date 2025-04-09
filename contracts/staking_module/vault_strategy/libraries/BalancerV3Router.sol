// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// OpenZeppelin imports
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// Balancer V3 imports
import "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IRouter.sol";
import "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/VaultTypes.sol";

/**
 * @title Helper contract for interacting with Balancer V3 pools.
 * @notice Provides functions to add/remove liquidity from Balancer V3 pools.
 * @dev This contract implements hooks required for the Balancer V3 unlock pattern.
 */
contract BalancerV3Router is ReentrancyGuardTransient, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant INTERACTOR_ROLE = keccak256("INTERACTOR_ROLE");

    IVault public immutable vault;

    /// @dev Only the Vault can call functions marked by this modifier.
    modifier onlyVault() {
        require(msg.sender == address(vault), "BalancerV3Router: caller is not the vault");
        _;
    }

    /**
     * @notice Constructs the helper with required Balancer V3 contracts.
     * @param _vault The Balancer V3 vault contract address.
     * @param _admin The address of the admin.
     * @param _interactors The addresses of the contracts that can interact with the router.
     */
    constructor(address _vault, address _admin, address[] memory _interactors) {
        vault = IVault(_vault);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setInteractors(_interactors);
    }

    // ================ Admin ================

    /**
     * @notice Updates the list of addresses that can interact with the router
     * @param _interactors Array of addresses to grant the INTERACTOR_ROLE to
     * @dev Only callable by admin. Grants INTERACTOR_ROLE to each address in the array.
     */
    function setInteractors(address[] memory _interactors) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setInteractors(_interactors);
    }

    /**
     * @dev Internal function to grant INTERACTOR_ROLE to an array of addresses
     * @param _interactors Array of addresses to grant the role to
     */
    function _setInteractors(address[] memory _interactors) internal {
        for (uint256 i = 0; i < _interactors.length; i++) {
            _grantRole(INTERACTOR_ROLE, _interactors[i]);
        }
    }

    // ================ Interactors ================

    /**
     * @notice Adds liquidity to a Balancer V3 pool with exact token amounts (unbalanced).
     * @param _pool The address of the Balancer pool.
     * @param _exactAmountsIn Array of token amounts to add, sorted by token address.
     * @param _minBptAmountOut Minimum BPT to receive as slippage protection.
     * @return bptAmountOut The amount of BPT tokens received.
     */
    function addLiquidityUnbalanced(
        address _pool,
        uint256[] memory _exactAmountsIn,
        uint256 _minBptAmountOut
    ) external onlyRole(INTERACTOR_ROLE) returns (uint256 bptAmountOut) {
        (, bptAmountOut,) = abi.decode(
            vault.unlock(
                abi.encodeCall(
                    this.addLiquidityHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: _pool,
                        maxAmountsIn: _exactAmountsIn,
                        minBptAmountOut: _minBptAmountOut,
                        kind: AddLiquidityKind.UNBALANCED
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );

        return bptAmountOut;
    }

    /**
     * @notice Removes liquidity from a Balancer V3 pool for a single token.
     * @param _pool The address of the Balancer pool.
     * @param _tokenOutIndex Index of the token to receive.
     * @param _exactBptAmountIn Exact BPT amount to burn.
     * @param _minAmountOut Minimum token amount to receive as slippage protection.
     * @return amountOut The amount of token received.
     */
    function removeLiquiditySingleTokenExactIn(
        address _pool,
        uint256 _tokenOutIndex,
        uint256 _exactBptAmountIn,
        uint256 _minAmountOut
    ) external onlyRole(INTERACTOR_ROLE) returns (uint256 amountOut) {
        // Create minAmountsOut array with only the token we want
        uint256[] memory minAmountsOut = new uint256[](vault.getPoolTokens(_pool).length);
        minAmountsOut[_tokenOutIndex] = _minAmountOut;

        (, uint256[] memory tokensOut,) = abi.decode(
            vault.unlock(
                abi.encodeCall(
                    this.removeLiquidityHook,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
                        pool: _pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: _exactBptAmountIn,
                        kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );

        return tokensOut[_tokenOutIndex];
    }

    /// ================ Hooks ================

    /**
     * @notice Parameters for adding liquidity to a Balancer V3 pool via hook
     * @param sender The address that initiated the add liquidity operation
     * @param pool The address of the Balancer pool to add liquidity to
     * @param maxAmountsIn Maximum amounts of each token to add as liquidity
     * @param minBptAmountOut Minimum BPT amount to receive as slippage protection
     * @param kind The type of add liquidity operation to perform
     */
    struct AddLiquidityHookParams {
        address sender;
        address pool;
        uint256[] maxAmountsIn;
        uint256 minBptAmountOut;
        AddLiquidityKind kind;
    }

    /**
     * @notice Hook for adding liquidity to a pool.
     * @dev Can only be called by the Vault.
     * @param params Add liquidity parameters
     * @return amountsIn Actual amounts in required for the join
     * @return bptAmountOut BPT amount minted in exchange for the input tokens
     * @return returnData Arbitrary data with encoded response from the pool
     */
    function addLiquidityHook(AddLiquidityHookParams calldata params)
        external
        nonReentrant
        onlyVault
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        (amountsIn, bptAmountOut, returnData) = vault.addLiquidity(
            AddLiquidityParams({
                pool: params.pool,
                to: params.sender,
                maxAmountsIn: params.maxAmountsIn,
                minBptAmountOut: params.minBptAmountOut,
                kind: params.kind,
                userData: bytes("")
            })
        );

        // getPoolTokens returns tokens in sorted order
        IERC20[] memory tokens = vault.getPoolTokens(params.pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amountIn = amountsIn[i];

            if (amountIn == 0) {
                continue;
            }

            // Settle the token
            token.safeTransferFrom(params.sender, address(vault), amountIn);
            vault.settle(token, amountIn);
        }
    }

    /**
     * @notice Parameters for removing liquidity from a Balancer V3 pool via hook
     * @param sender The address that initiated the remove liquidity operation
     * @param pool The address of the Balancer pool to remove liquidity from
     * @param minAmountsOut Minimum amounts of each token to receive as slippage protection
     * @param maxBptAmountIn Maximum BPT amount to burn
     * @param kind The type of remove liquidity operation to perform
     */
    struct RemoveLiquidityHookParams {
        address sender;
        address pool;
        uint256[] minAmountsOut;
        uint256 maxBptAmountIn;
        RemoveLiquidityKind kind;
    }

    /**
     * @notice Hook for removing liquidity from a pool.
     * @dev Can only be called by the Vault.
     * @param params Remove liquidity parameters
     * @return bptAmountIn BPT amount burned for the output tokens
     * @return amountsOut Actual token amounts transferred in exchange for the BPT
     * @return returnData Arbitrary data with an encoded response from the pool
     */
    function removeLiquidityHook(RemoveLiquidityHookParams calldata params)
        external
        nonReentrant
        onlyVault
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        (bptAmountIn, amountsOut, returnData) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: params.pool,
                from: params.sender,
                maxBptAmountIn: params.maxBptAmountIn,
                minAmountsOut: params.minAmountsOut,
                kind: params.kind,
                userData: bytes("")
            })
        );

        // minAmountsOut length is checked against tokens length at the Vault.
        IERC20[] memory tokens = vault.getPoolTokens(params.pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountOut = amountsOut[i];

            if (amountOut == 0) {
                continue;
            }

            // Send tokens to the recipient
            vault.sendTo(tokens[i], params.sender, amountOut);
        }
    }
}
