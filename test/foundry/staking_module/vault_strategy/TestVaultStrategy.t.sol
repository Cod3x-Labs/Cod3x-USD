// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {
    IVault,
    JoinKind,
    ExitKind,
    SwapKind
} from "contracts/staking_module/vault_strategy/interfaces/IVault.sol";
import {
    IComposableStablePoolFactory,
    IRateProvider,
    ComposableStablePool
} from "contracts/staking_module/vault_strategy/interfaces/IComposableStablePoolFactory.sol";
import "forge-std/console.sol";

import {TestCdxUSD} from "test/helpers/TestCdxUSD.sol";

// vault
import {ReaperBaseStrategyv4} from "lib/Cod3x-Vault/src/ReaperBaseStrategyv4.sol";
import {ReaperVaultV2} from "lib/Cod3x-Vault/src/ReaperVaultV2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestVaultStrategy is TestCdxUSD {
    bytes32 public poolId;
    address public poolAdd;
    IERC20[] public assets;

    function setUp() public virtual override {
        super.setUp();
        vm.selectFork(forkIdEth);

        assets = [IERC20(address(cdxUSD)), usdc, usdt];

        /// balancer stable pool creation
        (poolId, poolAdd) = createStablePool(assets, 2500, userA);

        /// join Pool
        (IERC20[] memory setupPoolTokens,,) = IVault(vault).getPoolTokens(poolId);
        uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);
        amountsToAdd[0] = INITIAL_CDXUSD_AMT;
        amountsToAdd[1] = INITIAL_USDT_AMT;
        amountsToAdd[2] = INITIAL_USDC_AMT;
        amountsToAdd[3] = 0;

        joinPool(poolId, setupPoolTokens, amountsToAdd, userA, JoinKind.INIT);

        // vault
        address[] memory ownerArr = new address[](3);
        ownerArr[0] = address(this);
        ownerArr[1] = address(this);
        ownerArr[2] = address(this);

        ReaperVaultV2 vault = new ReaperVaultV2(
            poolAdd,
            "Staked Cod3x USD",
            "scdxUSD",
            type(uint256).max,
            0,
            treasury,
            ownerArr,
            ownerArr,
            address(this)
        );

        // ReaperStrategyThenaHarbor implementation = new ReaperStrategyThenaHarbor();
        // ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        // ReaperStrategyThenaHarbor strategy = ReaperStrategyThenaHarbor(address(proxy));

        // initializeStrategy(
        //     strategy, address(vault), baseConfig.router, baseConfig.thenaGauge, baseConfig.swapSlippage
        // );

        // vault.addStrategy(address(strategy), feeBPS, allocation);
    }

    function testInitialBalance() public {
        assertEq(0, usdc.balanceOf(userA));
        assertEq(0, usdt.balanceOf(userA));
        assertEq(0, cdxUSD.balanceOf(userA));
        // assertEq(1e13, IERC20(poolAdd).balanceOf(userA));
    }
}
