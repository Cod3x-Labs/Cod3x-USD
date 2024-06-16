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

contract TestBalancerInterface is TestCdxUSD {
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
    }

    function testInitialBalance() public {
        assertEq(0, usdc.balanceOf(userA));
        assertEq(0, usdt.balanceOf(userA));
        assertEq(0, cdxUSD.balanceOf(userA));
        // assertEq(1e13, IERC20(poolAdd).balanceOf(userA));
    }

    function testExitPool() public {
        (IERC20[] memory setupPoolTokens,,) = IVault(vault).getPoolTokens(poolId);

        exitPool(
            poolId,
            setupPoolTokens,
            IERC20(poolAdd).balanceOf(userA) / 2,
            userA,
            ExitKind.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT
        );
        assertApproxEqRel(INITIAL_USDC_AMT / 2, usdc.balanceOf(userA), 1e15); // 0,1%
        assertApproxEqRel(INITIAL_USDT_AMT / 2, usdt.balanceOf(userA), 1e15); // 0,1%
        assertApproxEqRel(INITIAL_CDXUSD_AMT / 2, cdxUSD.balanceOf(userA), 1e15); // 0,1%
    }

    function testSwapAndJoin() public {
        logCash();

        /// Swap
        uint256 amt = 10000;

        assertEq(INITIAL_USDC_AMT, usdc.balanceOf(userB));
        assertEq(INITIAL_USDT_AMT, usdt.balanceOf(userB));
        assertEq(0, cdxUSD.balanceOf(userB));

        swap(
            poolId,
            userB,
            address(usdc),
            address(cdxUSD),
            amt * 10 ** 6,
            0,
            block.timestamp,
            SwapKind.GIVEN_IN
        );

        assertEq(INITIAL_USDC_AMT - amt * 10 ** 6, usdc.balanceOf(userB));
        assertEq(INITIAL_USDT_AMT, usdt.balanceOf(userB));
        assertApproxEqRel(amt * 10 ** 18, cdxUSD.balanceOf(userB), 1e15); // 0,1%

        logCash();
        /// Join
        (IERC20[] memory setupPoolTokens,,) = IVault(vault).getPoolTokens(poolId);

        uint256[] memory amountsToAdd = new uint256[](assets.length);
        // amountsToAdd[0] = 0;
        // amountsToAdd[1] = amt * 10**6;
        // amountsToAdd[2] = amt * 10**6;
        amountsToAdd[0] = cdxUSD.balanceOf(userB);
        amountsToAdd[1] = usdt.balanceOf(userB);
        amountsToAdd[2] = usdc.balanceOf(userB);

        joinPool(poolId, setupPoolTokens, amountsToAdd, userB, JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT);
        assertEq(0, usdc.balanceOf(userB));
        assertEq(0, usdt.balanceOf(userB));
        assertEq(0, cdxUSD.balanceOf(userB));
        assertGt(IERC20(poolAdd).balanceOf(userB), 0);

        logCash();
    }

    function logCash() public view {
        for (uint256 i = 0; i < assets.length; i++) {
            (uint256 cash,,,) = IVault(vault).getPoolTokenInfo(poolId, assets[i]);

            console.log(cash);
            // console.log(managed);
            // console.log("---");
        }
        console.log("totalSupply : ", IERC20(poolAdd).totalSupply());

        console.log("---");
    }

    // ------ helpers --------
}
