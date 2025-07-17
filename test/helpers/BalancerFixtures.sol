// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {StablePoolFactory} from
    "lib/balancer-v3-monorepo/pkg/pool-stable/contracts/StablePoolFactory.sol";
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
import {IRateProvider} from
    "lib/balancer-v3-monorepo/pkg/interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import {BalancerV3Router} from
    "contracts/staking_module/vault_strategy/libraries/BalancerV3Router.sol";
import "test/helpers/Sort.sol";
import "test/helpers/Constants.sol";
import {console2} from "forge-std/console2.sol";

contract BalancerFixtures is Sort, Constants {
    function createStablePool(IERC20[] memory assets, uint256 amplificationParameter, address owner)
        public
        returns (address)
    {
        // sort tokens
        IERC20[] memory tokens = new IERC20[](assets.length);

        tokens = sort(assets);
        TokenConfig[] memory tokenConfigs = new TokenConfig[](assets.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfigs[i] = TokenConfig({
                token: tokens[i],
                tokenType: TokenType.STANDARD,
                rateProvider: IRateProvider(address(0)),
                paysYieldFees: false
            });
        }
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.pauseManager = address(0);
        roleAccounts.swapFeeManager = address(0);
        roleAccounts.poolCreator = address(0);

        address stablePool = address(
            StablePoolFactory(address(balancerContracts.stablePoolFactory)).create(
                "Cod3x-USD-Pool",
                "CUP",
                tokenConfigs,
                amplificationParameter, // test only
                roleAccounts,
                1e12, // 0.001% (in WAD)
                address(0),
                false,
                false,
                bytes32(keccak256(abi.encode(tokenConfigs, bytes("Cod3x-USD-Pool"), bytes("CUP"))))
            )
        );

        return (address(stablePool));
    }
}
