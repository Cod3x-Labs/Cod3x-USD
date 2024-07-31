// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {TestCdxUSD, ERC20Mock} from "test/helpers/TestCdxUSD.sol";
import "contracts/facilitators/cod3x_lend/interest_strategy/CdxUSDPiInterestRateStrategy.sol";
import {BalancerVaultMock} from "test/helpers/mocks/BalancerVaultMock.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {ILendingPoolAddressesProvider} from
    "lib/granary-v2/contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {LendingPoolProviderMock} from "../../../helpers/mocks/LendingPoolProviderMock.sol";
// import "contracts/facilitators/flash_minter/CdxUSDFlashMinter.sol";
// import {MockFlashBorrower} from "../../helpers/mocks/MockFlashBorrower.sol";

contract CdxUSDPiInterestRateStrategyTest is TestCdxUSD {
    address admin;
    address provider;
    bytes32 poolId;
    address[] tokenAddresses;
    uint256[] balances;

    uint256 constant INITIAL_BALANCE = 1000;

    BalancerVaultMock balancerVaultMock;
    CdxUSDPiInterestRateStrategy cdxUSDPiInterestRateStrategy;

    string path1 =
        "./test/foundry/facilitators/interest_strategy/piGraphs/outputGreaterThanZero.csv";

    string path2 = "./test/foundry/facilitators/interest_strategy/piGraphs/outputLessThanZero.csv";

    function setUp() public override {
        super.setUp();

        provider = address(new LendingPoolProviderMock(makeAddr("lendingPool")));
        poolId = bytes32("cdxUSD/USDT/USDC");
        tokenAddresses = new address[](3);
        tokenAddresses[0] = address(usdc);
        tokenAddresses[1] = address(usdt);
        tokenAddresses[2] = address(cdxUSD);
        balances = new uint256[](3);
        for (uint8 idx = 0; idx < tokenAddresses.length; idx++) {
            balances[idx] = INITIAL_BALANCE * 10 ** ERC20Mock(tokenAddresses[idx]).decimals();
        }

        balancerVaultMock = new BalancerVaultMock(poolId, tokenAddresses, balances);

        // address[] memory balances_ = balancerVaultMock.getPoolTokens(poolId);
        // console.log(balances_[0]);
        // console.log(balancerVaultMock._idToTokens());
        admin = makeAddr("admin");

        cdxUSDPiInterestRateStrategy = new CdxUSDPiInterestRateStrategy(
            provider,
            address(cdxUSD),
            true,
            address(balancerVaultMock),
            poolId,
            -400e24, //Min controller error
            20 days, //maxITimeAmp
            1e27, //kp
            13e19, // ki
            admin
        );

        if (vm.exists(path1)) vm.removeFile(path1);
        vm.writeLine(
            path1,
            "timestamp,user,action,asset,utilizationRate,currentLiquidityRate,currentVariableBorrowRate"
        );

        if (vm.exists(path2)) vm.removeFile(path2);
        vm.writeLine(
            path2,
            "timestamp,user,action,asset,utilizationRate,currentLiquidityRate,currentVariableBorrowRate"
        );
    }

    function logg(address user, uint256 action, address asset, string memory path) public {
        vm.prank(ILendingPoolAddressesProvider(provider).getLendingPool());
        (, uint256 currentVariableBorrowRateCalc) =
            cdxUSDPiInterestRateStrategy.calculateInterestRates(address(0), address(0), 0, 0, 0, 0);
        // console.log("currentVariableBorrowRateCalc: ", currentVariableBorrowRateCalc);
        (uint256 currentLiquidityRate, uint256 currentVariableBorrowRate, uint256 utilizationRate) =
            cdxUSDPiInterestRateStrategy.getCurrentInterestRates();
        console.log("currentVariableBorrowRate: ", currentVariableBorrowRate);

        string memory data = string(
            abi.encodePacked(
                Strings.toString(block.timestamp),
                ",",
                Strings.toHexString(user),
                ",",
                Strings.toString(action),
                ",",
                Strings.toHexString(asset),
                ",",
                Strings.toString(utilizationRate),
                ",",
                Strings.toString(currentLiquidityRate),
                ",",
                Strings.toString(currentVariableBorrowRate)
            )
        );
        vm.writeLine(path, data);
    }

    function testPidWithErrGreaterThanZero() public {
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        balancerVaultMock.setBalancesForTokens(poolId, tokenAddresses, balances);
        logg(address(this), 0, address(cdxUSD), path1);

        balances[0] = 1000 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[1] = 800 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[2] = 1200 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        balancerVaultMock.setBalancesForTokens(poolId, tokenAddresses, balances);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path1);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path1);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path1);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path1);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path1);

        balances[0] = 900 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[1] = 1100 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[2] = 1000 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();
        balancerVaultMock.setBalancesForTokens(poolId, tokenAddresses, balances);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path1);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path1);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path1);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path1);
        vm.warp(block.timestamp + 1 days);
    }

    function testPidWithErrLessThanZero() public {
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        balancerVaultMock.setBalancesForTokens(poolId, tokenAddresses, balances);
        logg(address(this), 0, address(cdxUSD), path2);

        balances[0] = 2000 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[1] = 500 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[2] = 500 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();
        balancerVaultMock.setBalancesForTokens(poolId, tokenAddresses, balances);

        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path2);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path2);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path2);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path2);
        vm.warp(block.timestamp + 1 days);
        console.log(">>>>>>>>>>>>>>> Timestamp: ", block.timestamp / 1 days);
        logg(address(this), 0, address(cdxUSD), path2);
    }
}
