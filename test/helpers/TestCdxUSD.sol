// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/console2.sol";

/// LayerZero
// Mock imports
import {OFTMock} from "../helpers/mocks/OFTMock.sol";
import {ERC20Mock} from "../helpers/mocks/ERC20Mock.sol";
import {OFTComposerMock} from "../helpers/mocks/OFTComposerMock.sol";
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

// DevTools imports
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

/// Main import
import "@openzeppelin/contracts/utils/Strings.sol";
import "contracts/tokens/CdxUSD.sol";
import "contracts/interfaces/ICdxUSD.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "test/helpers/Events.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "test/helpers/BalancerFixtures.sol";

/// balancer V3 imports

// import {IVault} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import {Vault} from "lib/balancer-v3-monorepo/pkg/vault/contracts/Vault.sol";

import {TRouter} from "test/helpers/TRouter.sol";
import {IVaultExplorer} from
    "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVaultExplorer.sol";

contract TestCdxUSD is TestHelperOz5, Events, BalancerFixtures {
    uint32 aEid = 1;
    uint32 bEid = 2;

    uint128 public constant DEFAULT_CAPACITY = 100_000_000e18;
    uint128 public constant INITIAL_CDXUSD_AMT = 10_000_000e18;
    uint128 public constant INITIAL_USDT_AMT = 10_000_000e6;
    uint128 public constant INITIAL_USDC_AMT = 10_000_000e6;

    uint128 public constant INITIAL_ETH_MINT = 1000 ether;

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public userC = address(0x3);
    address public owner = address(this);
    address public guardian = address(0x4);
    // address public treasury = address(0x5);

    CdxUSD public cdxUSD;
    IERC20 public usdc;
    IERC20 public usdt;

    uint256 public forkIdEth;
    uint256 public forkIdPolygon;

    function setUp() public virtual override {
        super.setUp();

        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        forkIdEth = vm.createFork(MAINNET_RPC_URL);

        vm.deal(userA, INITIAL_ETH_MINT);
        vm.deal(userB, INITIAL_ETH_MINT);
        vm.deal(userC, INITIAL_ETH_MINT);

        setUpEndpoints(2, LibraryType.UltraLightNode);
        cdxUSD = CdxUSD(
            _deployOApp(
                type(CdxUSD).creationCode,
                abi.encode(
                    "aOFT", "aOFT", address(endpoints[aEid]), owner, extContracts.treasury, guardian
                )
            )
        );
        cdxUSD.addFacilitator(userA, "user a", DEFAULT_CAPACITY);

        usdc = IERC20(address(new ERC20Mock{salt: "1"}(6)));
        usdt = IERC20(address(new ERC20Mock{salt: "2"}(6)));

        /// initial mint
        ERC20Mock(address(usdc)).mint(userA, INITIAL_USDC_AMT);
        ERC20Mock(address(usdt)).mint(userA, INITIAL_USDT_AMT);

        ERC20Mock(address(usdc)).mint(userB, INITIAL_USDC_AMT);
        ERC20Mock(address(usdt)).mint(userB, INITIAL_USDT_AMT);

        ERC20Mock(address(usdc)).mint(userC, INITIAL_USDC_AMT);
        ERC20Mock(address(usdt)).mint(userC, INITIAL_USDT_AMT);

        vm.startPrank(userA);
        cdxUSD.mint(userA, INITIAL_CDXUSD_AMT);
        cdxUSD.mint(userB, INITIAL_CDXUSD_AMT);
        cdxUSD.mint(address(this), INITIAL_CDXUSD_AMT);
        vm.stopPrank();

        ERC20Mock(address(usdc)).mint(userB, INITIAL_USDC_AMT);
        ERC20Mock(address(usdt)).mint(userB, INITIAL_USDT_AMT);

        // MAX approve "vault" by all users
        for (uint160 i = 1; i <= 3; i++) {
            vm.startPrank(address(i)); // address(0x1) == address(1)
            cdxUSD.approve(balancerContracts.balVault, type(uint256).max);
            usdc.approve(balancerContracts.balVault, type(uint256).max);
            usdt.approve(balancerContracts.balVault, type(uint256).max);
            vm.stopPrank();
        }
    }
}
