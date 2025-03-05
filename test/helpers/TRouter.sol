// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// balancer V3 imports
import {BalancerHelperV3} from "contracts/staking_module/vault_strategy/libraries/BalancerHelperV3.sol";
import {
    TokenConfig,
    TokenType,
    PoolRoleAccounts,
    LiquidityManagement,
    AddLiquidityKind,
    RemoveLiquidityKind,
    AddLiquidityParams,
    RemoveLiquidityParams
} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import { Vault } from "lib/balancer-v3-monorepo/pkg/vault/contracts/Vault.sol";
import { StablePoolFactory } from "lib/balancer-v3-monorepo/pkg/pool-stable/contracts/StablePoolFactory.sol";
import { IRateProvider } from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IVaultExtension} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVaultExtension.sol";

import {Constants} from "./Constants.sol";

contract TRouter is Constants {

    constructor() {
        // cdxUsd.approve(address(vaultV3), type(uint256).max);
        // counterAsset.approve(address(vaultV3), type(uint256).max);
    }

    function initialize(
        address pool,
        IERC20[] memory tokens,
        uint256[] memory amounts
    ) public payable returns (uint256 bptAmountOut) {
        return
            abi.decode(
                Vault(vaultV3).unlock(
                    abi.encodeCall(
                        this.initializeHook,
                        (msg.sender, pool, tokens, amounts, 0, bytes(""))
                    )
                ),
                (uint256)
            );
    }
    
    function initializeHook(
        address sender,
        address pool,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256 minBptAmountOut,
        bytes memory userData
    ) public returns (uint256 bptAmountOut) {
        bptAmountOut = IVaultExtension(vaultV3).initialize(
            pool,
            sender,
            tokens,
            amounts,
            minBptAmountOut,
            userData
        );

       _settle(sender, pool, amounts);
    }


    function addLiquidity(
        address pool,
        address sender,
        uint256[] memory amounts
    ) public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        AddLiquidityParams memory addLiquidityParams;
        addLiquidityParams.pool = pool;
        addLiquidityParams.to = sender;
        addLiquidityParams.maxAmountsIn = amounts;
        addLiquidityParams.minBptAmountOut = 0;
        addLiquidityParams.kind = AddLiquidityKind.UNBALANCED;
        addLiquidityParams.userData = bytes("");
        
        (amountsIn, bptAmountOut, ) = abi.decode(
            Vault(vaultV3).unlock(
                abi.encodeCall(
                    this.addLiquidityHook,
                    addLiquidityParams
                )
            ),
            (uint256[], uint256, bytes)
        );
    }

    function addLiquidityHook(
        AddLiquidityParams memory params
    )
        public
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData)
    {
        (amountsIn, bptAmountOut, returnData) = Vault(vaultV3).addLiquidity(
            params
        );

        _settle(params.to, params.pool, params.maxAmountsIn);
    }

    function removeLiquidity(
        address pool,
        address sender,
        uint256[] memory minAmountsOut
    ) public returns (uint256[] memory amountsOut) {
        RemoveLiquidityParams memory removeLiquidityParams;
        removeLiquidityParams.pool = pool;
        removeLiquidityParams.from = sender;
        removeLiquidityParams.maxBptAmountIn = type(uint256).max;
        removeLiquidityParams.minAmountsOut = minAmountsOut;
        removeLiquidityParams.kind = RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT;
        removeLiquidityParams.userData = bytes("");

        (, amountsOut, ) = abi.decode(
            Vault(vaultV3).unlock(
                abi.encodeCall(this.removeLiquidityHook, removeLiquidityParams)
            ),
            (uint256, uint256[], bytes)
        );
    }

    function removeLiquidityHook(
        RemoveLiquidityParams memory params
    ) public returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData) {
        (bptAmountIn, amountsOut, returnData) = Vault(vaultV3).removeLiquidity(params);


        // minAmountsOut length is checked against tokens length at the Vault.
        IERC20[] memory tokens = IVault(vaultV3).getPoolTokens(params.pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 amountOut = amountsOut[i];
            if (amountOut == 0) {
                continue;
            }

            IERC20 token = tokens[i];

            // Transfer the token to the sender (amountOut).
            IVault(vaultV3).sendTo(token, params.from, amountOut);
        }
    }

    // ========== Internal Functions ==========

    function _settle(
        address sender,
        address pool,
        uint256[] memory amounts
    ) internal {
        IERC20[] memory tokens = IVault(vaultV3).getPoolTokens(pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amount = amounts[i];

            if (amount == 0) {
                continue;
            }

            token.transferFrom(sender, address(vaultV3), amount);
            Vault(vaultV3).settle(token, amount);
        }
    }

    receive() external payable {}

}