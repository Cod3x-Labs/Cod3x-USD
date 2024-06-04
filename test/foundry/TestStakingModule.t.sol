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
    IERC20[] public assets;

    function setUp() public virtual override {
        super.setUp();
        vm.selectFork(forkIdEth);

        assets = [IERC20(address(cdxUSD)), usdc, usdt];

        /// balancer stable pool creation
        poolId = createStablePool(
            "Cod3x-USD-Pool", "CUP", assets, 2500, userA
        );

        /// join Pool
        joinPool(poolId, userA, JoinKind.INIT);
    }

    function testInitialBalance() public {
        assertEq(0, usdc.balanceOf(userA));
        assertEq(0, usdt.balanceOf(userA));
        assertEq(0, cdxUSD.balanceOf(userA));
    }

    // ------ helpers --------
}
