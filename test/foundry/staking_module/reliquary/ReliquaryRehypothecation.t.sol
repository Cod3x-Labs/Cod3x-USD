// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "contracts/staking_module/reliquary/Reliquary.sol";
import "contracts/staking_module/reliquary/interfaces/IReliquary.sol";
import "contracts/staking_module/reliquary/nft_descriptors/NFTDescriptor.sol";
import "contracts/staking_module/reliquary/curves/LinearPlateauCurve.sol";
import "test/helpers/mocks/ERC20Mock.sol";
import "contracts/staking_module/reliquary/rehypothecation_adapters/GaugeBalancerV1.sol";
import "contracts/staking_module/reliquary/rehypothecation_adapters/GaugeBalancerV2.sol";

contract TestReliquaryRehypothecation is ERC721Holder, Test {
    using Strings for address;
    using Strings for uint256;

    Reliquary reliquary;
    LinearPlateauCurve linearPlateauCurve;
    ERC20Mock oath;
    ERC20Mock testToken;
    GaugeBalancerV1 gaugeBalancerV1;
    GaugeBalancerV2 gaugeBalancerV2;
    address nftDescriptor;
    address treasury = address(0xccc);
    uint256 emissionRate = 1e17;

    // Linear function config (to config)
    uint256 slope = 100; // Increase of multiplier every second
    uint256 minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)
    uint256 plateau = 10 days;
    int256[] public coeff = [int256(100e18), int256(1e18), int256(5e15), int256(-1e13), int256(5e9)];

    uint256 forkIdEth;
    address ezETHwETHPool = address(0x596192bB6e41802428Ac943D2f1476C1Af25CC0E);
    address ezETHwETHGauge = address(0xa8B309a75f0D64ED632d45A003c68A30e59A1D8b);
    address balToken = address(0xba100000625a3754423978a60c9317c58a424e3D);
    address ezEthToken = address(0xbf5495Efe5DB9ce00f80364C8B423567e58d2110);

    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        forkIdEth = vm.createFork(MAINNET_RPC_URL, 20133690);
        vm.selectFork(forkIdEth);

        int256[] memory coeffDynamic = new int256[](5);
        for (uint256 i = 0; i < 5; i++) {
            coeffDynamic[i] = coeff[i];
        }

        oath = new ERC20Mock(18);
        reliquary = new Reliquary(address(oath), emissionRate, "Reliquary Deposit", "RELIC");
        linearPlateauCurve = new LinearPlateauCurve(slope, minMultiplier, plateau);

        oath.mint(address(reliquary), 100_000_000 ether);

        nftDescriptor = address(new NFTDescriptor(address(reliquary)));

        reliquary.grantRole(keccak256("OPERATOR"), address(this));
        deal(ezETHwETHPool, address(this), 100_000_000 ether);
        IERC20(ezETHwETHPool).approve(address(reliquary), 1);
        reliquary.addPool(
            100,
            ezETHwETHPool,
            address(0),
            linearPlateauCurve,
            "ETH Pool",
            nftDescriptor,
            true,
            address(this)
        );

        address[] memory tokensToClaim_ = new address[](2);
        tokensToClaim_[0] = balToken;
        tokensToClaim_[1] = ezEthToken;

        gaugeBalancerV1 = new GaugeBalancerV1(
            address(reliquary), ezETHwETHGauge, ezETHwETHPool, address(this), tokensToClaim_
        );

        IERC20(ezETHwETHPool).approve(address(gaugeBalancerV1), type(uint256).max);
        IERC20(ezETHwETHPool).approve(address(reliquary), type(uint256).max);
        reliquary.setTreasury(treasury);
        reliquary.enableRehypothecation(0, address(gaugeBalancerV1));
    }

    function testGaugeBalancerDirectly(uint256 _seedAmt) public {
        address[] memory tokensToClaim_ = new address[](2);
        tokensToClaim_[0] = balToken;
        tokensToClaim_[1] = ezEthToken;

        GaugeBalancerV1 gaugeBalancerV1Temp = new GaugeBalancerV1(
            address(this), ezETHwETHGauge, ezETHwETHPool, address(this), tokensToClaim_
        );

        IERC20(ezETHwETHPool).approve(address(gaugeBalancerV1Temp), type(uint256).max);
        IERC20(ezETHwETHPool).approve(address(reliquary), type(uint256).max);
        reliquary.setTreasury(treasury);
        reliquary.enableRehypothecation(0, address(gaugeBalancerV1Temp));

        uint256 balanceBeforeBPT = IERC20(ezETHwETHPool).balanceOf(address(this));
        uint256 amt = bound(_seedAmt, 1000, balanceBeforeBPT);
        gaugeBalancerV1Temp.deposit(amt);
        skip(1 weeks);
        assertEq(balanceBeforeBPT - amt, IERC20(ezETHwETHPool).balanceOf(address(this)));

        // uint256 balanceBeforeEzEth = IERC20(ezEthToken).balanceOf(address(this));
        // uint256 balanceBeforeBal = IERC20(balToken).balanceOf(address(this));

        // console.log(IERC20(ezEthToken).balanceOf(address(gaugeBalancerV1Temp)));
        // console.log(IERC20(balToken).balanceOf(address(gaugeBalancerV1Temp)));

        // gaugeBalancerV1Temp.claim(address(this));

        // console.log(IERC20(ezEthToken).balanceOf(address(gaugeBalancerV1Temp)));
        // console.log(IERC20(balToken).balanceOf(address(gaugeBalancerV1Temp)));

        // assertGt(IERC20(ezEthToken).balanceOf(address(this)), balanceBeforeEzEth);
        // assertGt(IERC20(balToken).balanceOf(address(this)), balanceBeforeBal);

        gaugeBalancerV1Temp.withdraw(amt);
        assertEq(balanceBeforeBPT, IERC20(ezETHwETHPool).balanceOf(address(this)));
    }
}
