// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IRouter.sol";
import "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/VaultTypes.sol";

/**
 * @title Helper contract for interacting with Balancer V3 pools.
 * @notice Provides functions to add/remove liquidity from Balancer V3 pools.
 * @dev This contract implements hooks required for the Balancer V3 unlock pattern.
 */
contract BalancerV3Router is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Hook parameter structures
    struct AddLiquidityHookParams {
        address sender;
        address pool;
        uint256[] maxAmountsIn;
        uint256 minBptAmountOut;
        AddLiquidityKind kind;
        bytes userData;
    }

    struct RemoveLiquidityHookParams {
        address sender;
        address pool;
        uint256[] minAmountsOut;
        uint256 maxBptAmountIn;
        RemoveLiquidityKind kind;
        bytes userData;
    }

    IVault public immutable vault;

    /**
     * @dev Only the Vault can call functions marked by this modifier.
     */
    modifier onlyVault() {
        require(msg.sender == address(vault), "BalancerV3Router: caller is not the vault");
        _;
    }

    /**
     * @notice Constructs the helper with required Balancer V3 contracts.
     * @param _vault The Balancer V3 vault contract address.
     */
    constructor(IVault _vault) {
        vault = _vault;
    }

    /**
     * @notice Adds liquidity to a Balancer V3 pool with exact token amounts (unbalanced).
     * @param _pool The address of the Balancer pool.
     * @param _exactAmountsIn Array of token amounts to add, sorted by token address.
     * @param _minBptAmountOut Minimum BPT to receive as slippage protection.
     * @param _userData Optional user data for pool-specific join parameters.
     * @return bptAmountOut The amount of BPT tokens received.
     */
    function addLiquidityUnbalanced(
        address _pool,
        uint256[] memory _exactAmountsIn,
        uint256 _minBptAmountOut,
        bytes memory _userData
    ) external nonReentrant returns (uint256 bptAmountOut) {
        // Transfer tokens from user
        IERC20[] memory tokens = vault.getPoolTokens(_pool);
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (i < _exactAmountsIn.length && _exactAmountsIn[i] > 0) {
                tokens[i].safeTransferFrom(msg.sender, address(this), _exactAmountsIn[i]);
                tokens[i].forceApprove(address(vault), _exactAmountsIn[i]);
            }
        }

        (, bptAmountOut,) = abi.decode(
            vault.unlock(
                abi.encodeCall(
                    this.addLiquidityHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: _pool,
                        maxAmountsIn: _exactAmountsIn,
                        minBptAmountOut: _minBptAmountOut,
                        kind: AddLiquidityKind.UNBALANCED,
                        userData: _userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );

        return bptAmountOut;
    }

    /**
     * @notice Adds liquidity to a Balancer V3 pool with a single token, getting exact BPT out.
     * @param _pool The address of the Balancer pool.
     * @param _tokenIn The token to provide as liquidity.
     * @param _maxAmountIn Maximum amount of token to spend.
     * @param _exactBptAmountOut Exact BPT amount to receive.
     * @param _userData Optional user data for pool-specific join parameters.
     * @return amountIn The amount of token actually spent.
     */
    function addLiquiditySingleTokenExactOut(
        address _pool,
        IERC20 _tokenIn,
        uint256 _maxAmountIn,
        uint256 _exactBptAmountOut,
        bytes memory _userData
    ) external nonReentrant returns (uint256 amountIn) {
        // Transfer token from user
        _tokenIn.safeTransferFrom(msg.sender, address(this), _maxAmountIn);
        _tokenIn.forceApprove(address(vault), _maxAmountIn);

        // Find token index in pool
        (uint256 tokenIndex, bool tokenFound) = findTokenInPool(vault, _pool, _tokenIn);
        require(tokenFound, "Token not in pool");

        // Create maxAmountsIn array with only the token we're using
        uint256[] memory maxAmountsIn = new uint256[](vault.getPoolTokens(_pool).length);
        maxAmountsIn[tokenIndex] = _maxAmountIn;

        (uint256[] memory amountsIn,,) = abi.decode(
            vault.unlock(
                abi.encodeCall(
                    this.addLiquidityHook,
                    AddLiquidityHookParams({
                        sender: msg.sender,
                        pool: _pool,
                        maxAmountsIn: maxAmountsIn,
                        minBptAmountOut: _exactBptAmountOut,
                        kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                        userData: _userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );

        amountIn = amountsIn[tokenIndex];

        // Return unused tokens
        if (amountIn < _maxAmountIn) {
            _tokenIn.safeTransfer(msg.sender, _maxAmountIn - amountIn);
        }

        return amountIn;
    }

    /**
     * @notice Removes liquidity from a Balancer V3 pool proportionally.
     * @param _pool The address of the Balancer pool.
     * @param _exactBptAmountIn Exact BPT amount to burn.
     * @param _minAmountsOut Minimum token amounts to receive as slippage protection.
     * @param _userData Optional user data for pool-specific exit parameters.
     * @return amountsOut The amounts of tokens received.
     */
    function removeLiquidityProportional(
        address _pool,
        uint256 _exactBptAmountIn,
        uint256[] memory _minAmountsOut,
        bytes memory _userData
    ) external nonReentrant returns (uint256[] memory amountsOut) {
        // Approve BPT to the vault
        IERC20 bpt = IERC20(_pool);
        bpt.safeTransferFrom(msg.sender, address(this), _exactBptAmountIn);
        bpt.forceApprove(address(vault), _exactBptAmountIn);

        (, amountsOut,) = abi.decode(
            vault.unlock(
                abi.encodeCall(
                    this.removeLiquidityHook,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
                        pool: _pool,
                        minAmountsOut: _minAmountsOut,
                        maxBptAmountIn: _exactBptAmountIn,
                        kind: RemoveLiquidityKind.PROPORTIONAL,
                        userData: _userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );

        return amountsOut;
    }

    /**
     * @notice Removes liquidity from a Balancer V3 pool for a single token.
     * @param _pool The address of the Balancer pool.
     * @param _exactBptAmountIn Exact BPT amount to burn.
     * @param _tokenOut The token to receive.
     * @param _minAmountOut Minimum token amount to receive as slippage protection.
     * @param _userData Optional user data for pool-specific exit parameters.
     * @return amountOut The amount of token received.
     */
    function removeLiquiditySingleTokenExactIn(
        address _pool,
        uint256 _exactBptAmountIn,
        IERC20 _tokenOut,
        uint256 _minAmountOut,
        bytes memory _userData
    ) external nonReentrant returns (uint256 amountOut) {
        // Find token index in pool
        (uint256 tokenIndex, bool tokenFound) = findTokenInPool(vault, _pool, _tokenOut);
        require(tokenFound, "Token not in pool");

        // Create minAmountsOut array with only the token we want
        uint256[] memory minAmountsOut = new uint256[](vault.getPoolTokens(_pool).length);
        minAmountsOut[tokenIndex] = _minAmountOut;

        // Approve BPT to the vault
        IERC20 bpt = IERC20(_pool);
        bpt.safeTransferFrom(msg.sender, address(this), _exactBptAmountIn);
        bpt.forceApprove(address(vault), _exactBptAmountIn);

        (, uint256[] memory tokensOut,) = abi.decode(
            vault.unlock(
                abi.encodeCall(
                    this.removeLiquidityHook,
                    RemoveLiquidityHookParams({
                        sender: msg.sender,
                        pool: address(bpt),
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: _exactBptAmountIn,
                        kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                        userData: _userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );

        return tokensOut[tokenIndex];
    }

    /**
     *
     *                               Hook Functions
     *
     */

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
                userData: params.userData
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
            token.approve(address(vault), amountIn);
            vault.settle(token, amountIn);
        }
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
                from: address(this),
                maxBptAmountIn: params.maxBptAmountIn,
                minAmountsOut: params.minAmountsOut,
                kind: params.kind,
                userData: params.userData
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

    /**
     *
     *                             Query Functions
     *
     */

    /**
     * @notice Queries adding liquidity to a pool without executing the operation
     * @param _pool The address of the Balancer pool.
     * @param _exactAmountsIn Array of token amounts to add.
     * @param _userData Optional user data.
     * @return bptAmountOut The estimated amount of BPT tokens to be received.
     */
    function queryAddLiquidityUnbalanced(
        address _pool,
        uint256[] memory _exactAmountsIn,
        bytes memory _userData
    ) external nonReentrant returns (uint256 bptAmountOut) {
        (, bptAmountOut,) = abi.decode(
            vault.quote(
                abi.encodeCall(
                    this.queryAddLiquidityHook,
                    AddLiquidityHookParams({
                        sender: address(this),
                        pool: _pool,
                        maxAmountsIn: _exactAmountsIn,
                        minBptAmountOut: 0,
                        kind: AddLiquidityKind.UNBALANCED,
                        userData: _userData
                    })
                )
            ),
            (uint256[], uint256, bytes)
        );

        return bptAmountOut;
    }

    /**
     * @notice Queries removing liquidity from a pool without executing the operation
     * @param _pool The address of the Balancer pool.
     * @param _exactBptAmountIn Exact BPT amount to simulate burning.
     * @param _userData Optional user data.
     * @return amountsOut The estimated amounts of tokens to be received.
     */
    function queryRemoveLiquidityProportional(
        address _pool,
        uint256 _exactBptAmountIn,
        bytes memory _userData
    ) external nonReentrant returns (uint256[] memory amountsOut) {
        uint256[] memory minAmountsOut = new uint256[](vault.getPoolTokens(_pool).length);

        (, amountsOut,) = abi.decode(
            vault.quote(
                abi.encodeCall(
                    this.queryRemoveLiquidityHook,
                    RemoveLiquidityHookParams({
                        sender: address(this),
                        pool: _pool,
                        minAmountsOut: minAmountsOut,
                        maxBptAmountIn: _exactBptAmountIn,
                        kind: RemoveLiquidityKind.PROPORTIONAL,
                        userData: _userData
                    })
                )
            ),
            (uint256, uint256[], bytes)
        );

        return amountsOut;
    }

    /**
     * @notice Query hook for adding liquidity.
     * @dev Can only be called by the Vault.
     * @param params Add liquidity parameters
     * @return amountsIn Estimated token amounts in required
     * @return bptAmountOut Estimated BPT amount to be minted
     * @return returnData Arbitrary data from the pool
     */
    function queryAddLiquidityHook(AddLiquidityHookParams calldata params)
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
                userData: params.userData
            })
        );
    }

    /**
     * @notice Query hook for removing liquidity.
     * @dev Can only be called by the Vault.
     * @param params Remove liquidity parameters
     * @return bptAmountIn Estimated BPT amount to be burned
     * @return amountsOut Estimated token amounts to be received
     * @return returnData Arbitrary data from the pool
     */
    function queryRemoveLiquidityHook(RemoveLiquidityHookParams calldata params)
        external
        nonReentrant
        onlyVault
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData)
    {
        return vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: params.pool,
                from: params.sender,
                maxBptAmountIn: params.maxBptAmountIn,
                minAmountsOut: params.minAmountsOut,
                kind: params.kind,
                userData: params.userData
            })
        );
    }

    /**
     * @notice Checks if a token is part of a Balancer V3 pool.
     * @param _vault The Balancer V3 vault contract.
     * @param _pool The address of the Balancer pool.
     * @param _token The token to check.
     * @return index The index of the token in the pool (only valid if found is true).
     * @return found Whether the token was found in the pool.
     */
    function findTokenInPool(IVault _vault, address _pool, IERC20 _token)
        internal
        view
        returns (uint256 index, bool found)
    {
        IERC20[] memory tokens = _vault.getPoolTokens(_pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            if (address(tokens[i]) == address(_token)) {
                return (i, true);
            }
        }

        return (0, false);
    }
}
