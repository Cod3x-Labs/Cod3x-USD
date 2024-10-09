// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "contracts/interfaces/IBaseBalancerPool.sol";
import {
    IVault as IBalancerVault, JoinKind, ExitKind, SwapKind
} from "contracts/interfaces/IVault.sol"; // balancer Vault
import {IAsset} from "node_modules/@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import "forge-std/console.sol";

library BalancerHelper {
    /**
     * Help to join a balancer pool.
     * @param _balancerVault balancer vault.
     * @param _amounts sorted array of amounts to join. (without BPT)
     * @param _poolId pool index to join.
     * @param _poolTokens sorted array of the pool. (with BPT)
     * @param _minBPTAmountOut slippage protection. (in BPT)
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
     * Help to exit a balancer pool.
     * @param _balancerVault balancer vault.
     * @param _amount exact BPT amount to exit.
     * @param _poolId pool index to join.
     * @param _poolTokens sorted array of the pool. (with BPT)
     * @param _tokenToWithdraw token to withdraw.
     * @param _tokenIndex index of `_tokenToWithdraw` in the sorted array. (without BPT)
     * @param _minAmountOut slippage protection. (in _tokenToWithdraw)
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
     * Take a IERC20 array and return it without BPT.
     * @param _array IERC20 array to process.
     * @param _pool address of the pool.
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
