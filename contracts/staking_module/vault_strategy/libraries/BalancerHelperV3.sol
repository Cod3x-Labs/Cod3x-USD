// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "contracts/interfaces/IBaseBalancerPool.sol";
import {
    IVault as IBalancerVault, JoinKind, ExitKind, SwapKind
} from "contracts/interfaces/IVault.sol"; // balancer Vault
import {IAsset} from "node_modules/@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";

// TODO
/**
 * @title Helper library for interacting with Balancer V3 pools.
 * @notice Provides functions to join/exit Balancer V3 pools and handle BPT tokens.
 * @dev Implements common Balancer V3 pool operations with safety checks.
 */
library BalancerHelperV3 {
    /**
     * @notice Joins a Balancer pool with exact token amounts.
     * @dev Handles joining with multiple tokens and BPT minting.
     * @param _balancerVault The Balancer vault contract.
     * @param _amounts Array of token amounts to join with, sorted by token address.
     * @param _poolId The unique identifier of the Balancer pool.
     * @param _poolTokens Array of pool tokens including BPT, sorted by address.
     * @param _minBPTAmountOut Minimum BPT to receive as slippage protection.
     */
    function _joinPool(
        IBalancerVault _balancerVault,
        uint256[] memory _amounts,
        bytes32 _poolId,
        IAsset[] memory _poolTokens,
        uint256 _minBPTAmountOut
    ) internal {
        uint256 len_ = _poolTokens.length;

        uint256[] memory maxAmounts_ = new uint256[](len_);
        for (uint256 i = 0; i < len_; i++) {
            maxAmounts_[i] = type(uint256).max; // Ok. We always send balanceOf(address(this)).
        }

        IBalancerVault.JoinPoolRequest memory request;
        request.assets = _poolTokens;
        request.maxAmountsIn = maxAmounts_;
        request.fromInternalBalance = false;
        request.userData =
            abi.encode(JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, _amounts, _minBPTAmountOut);

        _balancerVault.joinPool(_poolId, address(this), address(this), request);
    }

    /**
     * @notice Exits a Balancer pool for a single token.
     * @dev Burns exact BPT amount to receive a specific token.
     * @param _balancerVault The Balancer vault contract.
     * @param _amount Exact BPT amount to burn.
     * @param _poolId The unique identifier of the Balancer pool.
     * @param _poolTokens Array of pool tokens including BPT, sorted by address.
     * @param _tokenToWithdraw Address of token to receive.
     * @param _tokenIndex Index of withdrawal token in sorted array (excluding BPT).
     * @param _minAmountOut Minimum token amount to receive as slippage protection.
     */
    function _exitPool(
        IBalancerVault _balancerVault,
        uint256 _amount,
        bytes32 _poolId,
        IAsset[] memory _poolTokens,
        address _tokenToWithdraw,
        uint256 _tokenIndex,
        uint256 _minAmountOut
    ) internal {
        uint256 len_ = _poolTokens.length;
        uint256[] memory minAmountsOut_ = new uint256[](len_);
        for (uint256 i = 0; i < len_; i++) {
            if (address(_poolTokens[i]) == _tokenToWithdraw) {
                minAmountsOut_[i] = _minAmountOut;
                break;
            }
        }

        IBalancerVault.ExitPoolRequest memory request;
        request.assets = _poolTokens;
        request.minAmountsOut = minAmountsOut_;
        request.toInternalBalance = false;
        request.userData = abi.encode(ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, _amount, _tokenIndex);

        _balancerVault.exitPool(_poolId, address(this), payable(address(this)), request);
    }

    /**
     * @notice Creates a new array excluding the BPT token.
     * @dev Used to handle arrays that need BPT filtered out.
     * @param _array Original array of tokens including BPT.
     * @param _pool Address of the Balancer pool.
     * @return Array of tokens with BPT removed.
     */
    function _dropBptItem(IERC20[] memory _array, address _pool)
        internal
        view
        returns (IERC20[] memory)
    {
        IERC20[] memory arrayWithoutBpt_ = new IERC20[](_array.length - 1);
        uint256 bptIndex_ = IBaseBalancerPool(_pool).getBptIndex();
        for (uint256 i = 0; i < arrayWithoutBpt_.length; i++) {
            arrayWithoutBpt_[i] = _array[i < bptIndex_ ? i : i + 1];
        }

        return arrayWithoutBpt_;
    }
}
