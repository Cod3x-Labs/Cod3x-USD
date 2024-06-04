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
import {IVault} from "test/helpers/interfaces/IVault.sol";
import {ERC20UsdMock} from "test/mocks/ERC20UsdMock.sol";
import "test/helpers/Constants.sol";
import {
    IComposableStablePoolFactory,
    IRateProvider,
    ComposableStablePool
} from "test/helpers/interfaces/IComposableStablePoolFactory.sol";
import {IAsset} from "node_modules/@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import {IVault, JoinKind, ExitKind, SwapKind} from "test/helpers/interfaces/IVault.sol";
import "forge-std/console2.sol";

contract TestCdxUSD is TestHelperOz5, Events, Constants {
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
    address public treasury = address(0x5);

    CdxUSD public cdxUSD;
    IERC20 public usdc;
    IERC20 public usdt;

    uint256 public forkIdEth;

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
                abi.encode("aOFT", "aOFT", address(endpoints[aEid]), owner, treasury, guardian)
            )
        );
        cdxUSD.addFacilitator(userA, "user a", DEFAULT_CAPACITY);

        usdc = IERC20(address(new ERC20UsdMock{salt: "1"}("USDC", "USDC")));
        usdt = IERC20(address(new ERC20UsdMock{salt: "1"}("USDT", "USDT")));

        /// initial mint
        ERC20UsdMock(address(usdc)).mint(userA, INITIAL_USDT_AMT);
        ERC20UsdMock(address(usdt)).mint(userA, INITIAL_USDT_AMT);

        vm.prank(userA); 
        cdxUSD.mint(userA, INITIAL_CDXUSD_AMT);

        // MAX approve "vault" by all users
        for (uint160 i = 1; i <= 3; i++) {
            vm.startPrank(address(i)); // address(0x1) == address(1)
            cdxUSD.approve(vault, type(uint256).max);
            usdc.approve(vault, type(uint256).max);
            usdt.approve(vault, type(uint256).max);
            vm.stopPrank();
        }
    }
    function createStablePool(        
        string memory name,
        string memory symbol,
        IERC20[] memory assets,
        uint256 amplificationParameter,
        address owner
    ) public returns (bytes32 poolId) {
        // sort tokens
        IERC20[] memory tokens = new IERC20[](assets.length);

        tokens = sortIERC20(assets);

        IRateProvider[] memory rateProviders = new IRateProvider[](3);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = IRateProvider(address(0));
        rateProviders[2] = IRateProvider(address(0));

        uint256[] memory tokenRateCacheDurations = new uint256[](3);
        tokenRateCacheDurations[0] = uint256(0);
        tokenRateCacheDurations[1] = uint256(0);
        tokenRateCacheDurations[2] = uint256(0);

        ComposableStablePool stablePool = IComposableStablePoolFactory(
            address(composableStablePoolFactory)
        ).create(
            name,
            symbol,
            tokens,
            2500, // test only
            rateProviders,
            tokenRateCacheDurations,
            false,
            1e12,
            owner,
            bytes32("")
        );
        poolId = stablePool.getPoolId();
        console.logBytes32(poolId);
    }

    function joinPool(bytes32 poolId, /*uint256[] memory amounts, */ address user, JoinKind kind) public {
        (IERC20[] memory setupPoolTokens,,) = IVault(vault).getPoolTokens(poolId);

        IERC20[] memory tokens = new IERC20[](setupPoolTokens.length);
        tokens = sortIERC20(setupPoolTokens);

        IAsset[] memory assetsIAsset = new IAsset[](setupPoolTokens.length);
        for (uint i = 0; i < setupPoolTokens.length; i++) {
            assetsIAsset[i] = IAsset(address(tokens[i]));
        }
        
        uint256[] memory maxAmounts = new uint256[](setupPoolTokens.length);
        for (uint i = 0; i < setupPoolTokens.length; i++) {
            maxAmounts[i] = type(uint256).max;
        }

        uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);
        amountsToAdd[0] = INITIAL_CDXUSD_AMT;
        amountsToAdd[1] = INITIAL_USDT_AMT;
        amountsToAdd[2] = INITIAL_USDC_AMT;
        amountsToAdd[3] = 1e13;

        IVault.JoinPoolRequest memory request;
        request.assets = assetsIAsset;
        request.maxAmountsIn = maxAmounts;
        request.fromInternalBalance = false;
        request.userData = abi.encode(kind, amountsToAdd);

        vm.prank(user);
        IVault(vault).joinPool(poolId, user, user, request);
    }

    // ----- helpers -----

    function quickSort(uint[] memory arr, int left, int right) internal pure {
        int i = left;
        int j = right;
        if (i == j) return;
        uint pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j)
            quickSort(arr, left, j);
        if (i < right)
            quickSort(arr, i, right);
    }

    function sort(uint[] memory data) public pure returns (uint[] memory) {
        quickSort(data, int(0), int(data.length - 1));
        return data;
    }

    function sortIERC20(IERC20[] memory data) public pure returns (IERC20[] memory retIERC20) {
        uint256[] memory arr = new uint256[](data.length);
        uint256[] memory arrr = new uint256[](data.length);
        retIERC20 = new IERC20[](data.length);

        for (uint i = 0; i < data.length; i++) {
            arr[i] = uint256(uint160(address(data[i])));
        }

        arrr = sort(arr);

        for (uint i = 0; i < data.length; i++) {
            retIERC20[i] = IERC20(address(uint160((arrr[i]))));
        }
    }

}