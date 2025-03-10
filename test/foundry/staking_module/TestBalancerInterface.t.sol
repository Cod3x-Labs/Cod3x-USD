// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.22;

// import "forge-std/console2.sol";

// import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
// import {TestCdxUSD} from "test/helpers/TestCdxUSD.sol";

// contract TestBalancerInterface is TestCdxUSD {
//     bytes32 public poolId;
//     address public poolAdd;
//     IERC20[] public assets;

//     uint256 public indexCdxUsd;
//     uint256 public indexUsdt;
//     uint256 public indexUsdc;

//     function setUp() public virtual override {
//         super.setUp();
//         vm.selectFork(forkIdEth);

//         assets = [IERC20(address(cdxUSD)), usdc, usdt];

//         /// balancer stable pool creation
//         (poolId, poolAdd) = createStablePool(assets, 2500, userA);

//         /// join Pool
//         (IERC20[] memory setupPoolTokens,,) = IVault(vault).getPoolTokens(poolId);

//         uint256 indexCdxUsdTemp;
//         uint256 indexUsdtTemp;
//         uint256 indexUsdcTemp;
//         uint256 indexBtpTemp;
//         for (uint256 i = 0; i < setupPoolTokens.length; i++) {
//             if (setupPoolTokens[i] == cdxUSD) indexCdxUsdTemp = i;
//             if (setupPoolTokens[i] == usdt) indexUsdtTemp = i;
//             if (setupPoolTokens[i] == usdc) indexUsdcTemp = i;
//             if (setupPoolTokens[i] == IERC20(poolAdd)) indexBtpTemp = i;
//         }

//         uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);
//         amountsToAdd[indexCdxUsdTemp] = INITIAL_CDXUSD_AMT;
//         amountsToAdd[indexUsdtTemp] = INITIAL_USDT_AMT;
//         amountsToAdd[indexUsdcTemp] = INITIAL_USDC_AMT;
//         amountsToAdd[indexBtpTemp] = 0;

//         joinPool(poolId, setupPoolTokens, amountsToAdd, userA, JoinKind.INIT);

//         IERC20[] memory setupPoolTokensWithoutBTP =
//             BalancerHelper._dropBptItem(setupPoolTokens, poolAdd);

//         for (uint256 i = 0; i < setupPoolTokensWithoutBTP.length; i++) {
//             if (setupPoolTokensWithoutBTP[i] == cdxUSD) indexCdxUsd = i;
//             if (setupPoolTokensWithoutBTP[i] == usdt) indexUsdt = i;
//             if (setupPoolTokensWithoutBTP[i] == usdc) indexUsdc = i;
//         }
//     }

//     function testInitialBalance() public {
//         assertEq(0, usdc.balanceOf(userA));
//         assertEq(0, usdt.balanceOf(userA));
//         assertEq(0, cdxUSD.balanceOf(userA));
//         // assertEq(1e13, IERC20(poolAdd).balanceOf(userA));
//     }

//     function testExitPool() public {
//         (IERC20[] memory setupPoolTokens,,) = IVault(vault).getPoolTokens(poolId);

//         exitPool(
//             poolId,
//             setupPoolTokens,
//             IERC20(poolAdd).balanceOf(userA) / 2,
//             userA,
//             ExitKind.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT
//         );
//         assertApproxEqRel(INITIAL_USDC_AMT / 2, usdc.balanceOf(userA), 1e15); // 0,1%
//         assertApproxEqRel(INITIAL_USDT_AMT / 2, usdt.balanceOf(userA), 1e15); // 0,1%
//         assertApproxEqRel(INITIAL_CDXUSD_AMT / 2, cdxUSD.balanceOf(userA), 1e15); // 0,1%
//     }

//     function testSwapAndJoin() public {
//         logCash();

//         /// Swap
//         uint256 amt = 10000;

//         assertEq(INITIAL_USDC_AMT * 2, usdc.balanceOf(userB));
//         assertEq(INITIAL_USDT_AMT * 2, usdt.balanceOf(userB));
//         assertEq(INITIAL_CDXUSD_AMT, cdxUSD.balanceOf(userB));

//         swap(
//             poolId,
//             userB,
//             address(usdc),
//             address(cdxUSD),
//             amt * 10 ** 6,
//             0,
//             block.timestamp,
//             SwapKind.GIVEN_IN
//         );

//         assertEq(INITIAL_USDC_AMT * 2 - amt * 10 ** 6, usdc.balanceOf(userB));
//         assertEq(INITIAL_USDT_AMT * 2, usdt.balanceOf(userB));
//         assertApproxEqRel(INITIAL_CDXUSD_AMT + amt * 10 ** 18, cdxUSD.balanceOf(userB), 1e15); // 0,1%

//         logCash();
//         /// Join
//         (IERC20[] memory setupPoolTokens,,) = IVault(vault).getPoolTokens(poolId);

//         uint256[] memory amountsToAdd = new uint256[](assets.length);
//         amountsToAdd[indexCdxUsd] = cdxUSD.balanceOf(userB);
//         amountsToAdd[indexUsdt] = usdt.balanceOf(userB);
//         amountsToAdd[indexUsdc] = usdc.balanceOf(userB);

//         joinPool(poolId, setupPoolTokens, amountsToAdd, userB, JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT);
//         assertEq(0, usdc.balanceOf(userB), "01");
//         assertEq(0, usdt.balanceOf(userB), "02");
//         assertEq(0, cdxUSD.balanceOf(userB), "03");
//         assertGt(IERC20(poolAdd).balanceOf(userB), 0, "04");

//         logCash();
//     }

//     function logCash() public view {
//         for (uint256 i = 0; i < assets.length; i++) {
//             (uint256 cash,,,) = IVault(vault).getPoolTokenInfo(poolId, assets[i]);

//             console2.log(cash);
//             // console2.log(managed);
//             // console2.log("---");
//         }
//         console2.log("totalSupply : ", IERC20(poolAdd).totalSupply());

//         console2.log("---");
//     }

//     // ------ helpers --------
// }
