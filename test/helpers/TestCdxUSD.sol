// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

/// LayerZero
// Mock imports
import {OFTMock} from "../helpers/mocks/OFTMock.sol";
import {ERC20Mock} from "../helpers/mocks/ERC20Mock.sol";
import {OFTComposerMock} from "../helpers/mocks/OFTComposerMock.sol";
import {IOFTExtended} from "contracts/tokens/interfaces/IOFTExtended.sol";

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
import "contracts/tokens/interfaces/ICdxUSD.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "test/helpers/Events.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IVault} from "test/helpers/interfaces/IVault.sol";
import "test/helpers/Constants.sol";
import "test/helpers/Sort.sol";
import {
    IComposableStablePoolFactory,
    IRateProvider,
    ComposableStablePool
} from "test/helpers/interfaces/IComposableStablePoolFactory.sol";
import {IAsset} from "node_modules/@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import {IVault, JoinKind, ExitKind, SwapKind} from "test/helpers/interfaces/IVault.sol";
import "forge-std/console2.sol";

contract TestCdxUSD is TestHelperOz5, Sort, Events, Constants {
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
        forkIdEth = vm.createFork(MAINNET_RPC_URL, 20077043);

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

        usdc = IERC20(address(new ERC20Mock{salt: "1"}(6)));
        usdt = IERC20(address(new ERC20Mock{salt: "2"}(6)));

        /// initial mint
        ERC20Mock(address(usdc)).mint(userA, INITIAL_USDC_AMT);
        ERC20Mock(address(usdt)).mint(userA, INITIAL_USDT_AMT);

        ERC20Mock(address(usdc)).mint(userB, INITIAL_USDC_AMT);
        ERC20Mock(address(usdt)).mint(userB, INITIAL_USDT_AMT);

        ERC20Mock(address(usdc)).mint(userC, INITIAL_USDC_AMT);
        ERC20Mock(address(usdt)).mint(userC, INITIAL_USDT_AMT);

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
        IERC20[] memory assets,
        uint256 amplificationParameter,
        address owner
    ) public returns (bytes32, address) {
        // sort tokens
        IERC20[] memory tokens = new IERC20[](assets.length);

        tokens = sort(assets);

        IRateProvider[] memory rateProviders = new IRateProvider[](3);
        for (uint i = 0; i < assets.length; i++) {
            rateProviders[i] = IRateProvider(address(0));
        }   

        uint256[] memory tokenRateCacheDurations = new uint256[](3);
        for (uint i = 0; i < assets.length; i++) {
            tokenRateCacheDurations[i] = uint256(0);
        }

        ComposableStablePool stablePool = IComposableStablePoolFactory(
            address(composableStablePoolFactory)
        ).create(
            "Cod3x-USD-Pool",
            "CUP",
            tokens,
            2500, // test only
            rateProviders,
            tokenRateCacheDurations,
            false,
            1e12,
            owner,
            bytes32("")
        );

        return (stablePool.getPoolId(), address(stablePool));
    }

    function joinPool(bytes32 poolId, IERC20[] memory setupPoolTokens, uint256[] memory amounts, address user, JoinKind kind) public {
        require(kind == JoinKind.INIT || kind == JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, "Operation not supported");

        IERC20[] memory tokens = new IERC20[](setupPoolTokens.length);
        uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);

        (tokens, amountsToAdd) = sort(setupPoolTokens, amounts);

        IAsset[] memory assetsIAsset = new IAsset[](setupPoolTokens.length);
        for (uint i = 0; i < setupPoolTokens.length; i++) {
            assetsIAsset[i] = IAsset(address(tokens[i]));
        }
        
        uint256[] memory maxAmounts = new uint256[](setupPoolTokens.length);
        for (uint i = 0; i < setupPoolTokens.length; i++) {
            maxAmounts[i] = type(uint256).max;
        }

        IVault.JoinPoolRequest memory request;
        request.assets = assetsIAsset;
        request.maxAmountsIn = maxAmounts;
        request.fromInternalBalance = false;
        if (kind == JoinKind.INIT)
            request.userData = abi.encode(kind, amountsToAdd);
        else if (kind == JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT)
            request.userData = abi.encode(kind, amountsToAdd, 0);
        
        vm.prank(user);
        IVault(vault).joinPool(poolId, user, user, request);
    }

    function exitPool(bytes32 poolId, IERC20[] memory setupPoolTokens, uint256 amount, address user, ExitKind kind) public {
        require(kind == ExitKind.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT, "Operation not supported");

        IERC20[] memory tokens = new IERC20[](setupPoolTokens.length);

        tokens = sort(setupPoolTokens);

        IAsset[] memory assetsIAsset = new IAsset[](setupPoolTokens.length);
        for (uint i = 0; i < setupPoolTokens.length; i++) {
            assetsIAsset[i] = IAsset(address(tokens[i]));
        }
        
        uint256[] memory minAmountsOut = new uint256[](setupPoolTokens.length);
        for (uint i = 0; i < setupPoolTokens.length; i++) {
            minAmountsOut[i] = 0;
        }

        IVault.ExitPoolRequest memory request;
        request.assets = assetsIAsset;
        request.minAmountsOut = minAmountsOut;
        request.toInternalBalance = false;
        request.userData = abi.encode(kind, amount);

        vm.prank(user);
        IVault(vault).exitPool(poolId, user, payable(user), request);
    }

    function swap(bytes32 poolId, address user, address assetIn, address assetOut, uint256 amount, uint256 limit, uint256 deadline, SwapKind kind) public {
        require(kind == SwapKind.GIVEN_IN, "Operation not supported");

        IVault.SingleSwap memory singleSwap;
        singleSwap.poolId = poolId;
        singleSwap.kind = kind;
        singleSwap.assetIn = IAsset(assetIn);
        singleSwap.assetOut = IAsset(assetOut);
        singleSwap.amount = amount;
        singleSwap.userData = bytes("");

        IVault.FundManagement memory fundManagement;
        fundManagement.sender = user;
        fundManagement.fromInternalBalance = false;
        fundManagement.recipient = payable(user);
        fundManagement.toInternalBalance = false;

        vm.prank(user);
        IVault(vault).swap(singleSwap, fundManagement, limit, deadline);
    }

}