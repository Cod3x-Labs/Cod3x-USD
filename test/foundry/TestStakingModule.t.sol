// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// LayerZero
// Mock imports
import {OFTMock} from "../mocks/OFTMock.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {OFTComposerMock} from "../mocks/OFTComposerMock.sol";
import {IOFTExtended} from "contracts/interfaces/IOFTExtended.sol";

// OApp imports
import {
    IOAppOptionsType3,
    EnforcedOptionParam
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import {
    IOFT,
    SendParam,
    OFTReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {
    MessagingFee, MessagingReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {OFTMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";
import {OFTComposeMsgCodec} from
    "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";

/// Main import
import "@openzeppelin/contracts/utils/Strings.sol";
import "contracts/tokens/CdxUSD.sol";
import "contracts/interfaces/ICdxUSD.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "test/helpers/Events.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IVault, JoinKind, ExitKind, SwapKind} from "test/helpers/interfaces/IVault.sol";
import {ERC20UsdMock} from "test/mocks/ERC20UsdMock.sol";
import "test/helpers/Constants.sol";
import {
    IComposableStablePoolFactory,
    IRateProvider,
    ComposableStablePool
} from "test/helpers/interfaces/IComposableStablePoolFactory.sol";
import {IAsset} from "node_modules/@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import "forge-std/console2.sol";

import {TestCdxUSD} from "test/helpers/TestCdxUSD.sol";

contract TestStakingModule is TestCdxUSD {
    bytes32 public poolId;
    address public poolAdd;
    IERC20[] public assets;

    function setUp() public virtual override {
        super.setUp();
        vm.selectFork(forkIdEth);

        assets = [IERC20(address(cdxUSD)), usdc, usdt];

        /// balancer stable pool creation
        (poolId, poolAdd) = createStablePool(
            assets, 2500, userA
        );

        /// join Pool
        (IERC20[] memory setupPoolTokens,,) = IVault(vault).getPoolTokens(poolId);
        uint256[] memory amountsToAdd = new uint256[](assets.length + 1);
        amountsToAdd[0] = INITIAL_CDXUSD_AMT;
        amountsToAdd[1] = INITIAL_USDT_AMT;
        amountsToAdd[2] = INITIAL_USDC_AMT;
        amountsToAdd[3] = 1e13;

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

        exitPool(poolId, setupPoolTokens, IERC20(poolAdd).balanceOf(userA) / 2, userA, ExitKind.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT);
        assertApproxEqRel(INITIAL_USDC_AMT / 2, usdc.balanceOf(userA), 1e15); // 0,1%
        assertApproxEqRel(INITIAL_USDT_AMT / 2, usdt.balanceOf(userA), 1e15); // 0,1%
        assertApproxEqRel(INITIAL_CDXUSD_AMT / 2, cdxUSD.balanceOf(userA), 1e15); // 0,1%
    }

    function testSwap() public {
        uint256 amt = 1000;

        assertEq(INITIAL_USDC_AMT, usdc.balanceOf(userB));
        assertEq(INITIAL_USDT_AMT, usdt.balanceOf(userB));
        assertEq(0, cdxUSD.balanceOf(userB));

        swap(poolId, userB, address(usdc), address(cdxUSD), amt * 10 ** 6, 0, block.timestamp, SwapKind.GIVEN_IN);

        assertEq(INITIAL_USDC_AMT  - amt * 10 ** 6, usdc.balanceOf(userB));
        assertEq(INITIAL_USDT_AMT, usdt.balanceOf(userB));
        assertApproxEqRel(amt * 10 ** 18, cdxUSD.balanceOf(userB), 1e15); // 0,1%
    }

    // ------ helpers --------
}
