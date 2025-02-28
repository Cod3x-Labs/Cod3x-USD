// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {TestCdxUSD, ERC20Mock} from "test/helpers/TestCdxUSD.sol";
import "contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol";
import {BalancerVaultMock} from "test/helpers/mocks/BalancerVaultMock.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {ILendingPoolAddressesProvider} from
    "lib/Cod3x-Lend/contracts/interfaces/ILendingPoolAddressesProvider.sol";
import {LendingPoolProviderMock} from "../../../helpers/mocks/LendingPoolProviderMock.sol";
import "forge-std/console2.sol";
// import "contracts/facilitators/flash_minter/CdxUSDFlashMinter.sol";
// import {MockFlashBorrower} from "../../helpers/mocks/MockFlashBorrower.sol";

contract CdxUsdIInterestRateStrategyTest is TestCdxUSD {
    address admin;
    address provider;
    bytes32 poolId;
    address[] tokenAddresses;

    uint256 constant INITIAL_BALANCE = 1000;

    BalancerVaultMock balancerVaultMock;
    CdxUsdIInterestRateStrategy cdxUsdIInterestRateStrategy;

    string path1 =
        "./test/foundry/facilitators/interest_strategy/piGraphs/outputGreaterThanZero.csv";

    string path2 = "./test/foundry/facilitators/interest_strategy/piGraphs/outputLessThanZero.csv";

    string path3 = "./test/foundry/facilitators/interest_strategy/piGraphs/outputMixed.csv";

    string path4 = "./test/foundry/facilitators/interest_strategy/piGraphs/outputMixed2.csv";

    function setUp() public override {
        super.setUp();

        uint256[] memory balances = new uint256[](3);
        balances[0] = 1000;
        balances[1] = 1000;
        balances[2] = 1000;

        provider = address(new LendingPoolProviderMock(makeAddr("lendingPool")));
        poolId = bytes32("cdxUSD/USDT/USDC");
        tokenAddresses = new address[](3);
        tokenAddresses[0] = address(usdc);
        tokenAddresses[1] = address(usdt);
        tokenAddresses[2] = address(cdxUSD);

        balancerVaultMock = new BalancerVaultMock(poolId, tokenAddresses, balances);

        // address[] memory balances_ = balancerVaultMock.getPoolTokens(poolId);
        // console2.log(balances_[0]);
        // console2.log(balancerVaultMock._idToTokens());
        admin = makeAddr("admin");

        cdxUsdIInterestRateStrategy = new CdxUsdIInterestRateStrategy(
            provider,
            address(cdxUSD),
            true,
            address(balancerVaultMock),
            poolId,
            1e25, // 1%
            2e25, // starts at 2% interest rate
            13e19 // ki
        );

        if (vm.exists(path1)) vm.removeFile(path1);
        vm.writeLine(
            path1,
            "timestamp,user,action,asset,utilizationRate,currentLiquidityRate,currentVariableBorrowRate,optimalStablePoolReserveUtilization"
        );

        if (vm.exists(path2)) vm.removeFile(path2);
        vm.writeLine(
            path2,
            "timestamp,user,action,asset,utilizationRate,currentLiquidityRate,currentVariableBorrowRate,optimalStablePoolReserveUtilization"
        );

        if (vm.exists(path3)) vm.removeFile(path3);
        vm.writeLine(
            path3,
            "timestamp,user,action,asset,utilizationRate,currentLiquidityRate,currentVariableBorrowRate,optimalStablePoolReserveUtilization"
        );

        if (vm.exists(path4)) vm.removeFile(path4);
        vm.writeLine(
            path4,
            "timestamp,user,action,asset,utilizationRate,currentLiquidityRate,currentVariableBorrowRate,optimalStablePoolReserveUtilization"
        );
    }

    function logg(address user, uint256 action, address asset, string memory path) public {
        vm.prank(ILendingPoolAddressesProvider(provider).getLendingPool());
        (, uint256 currentVariableBorrowRateCalc) =
            cdxUsdIInterestRateStrategy.calculateInterestRates(address(0), address(0), 0, 0, 0, 0);
        // console2.log("currentVariableBorrowRateCalc: ", currentVariableBorrowRateCalc);
        (uint256 currentLiquidityRate, uint256 currentVariableBorrowRate, uint256 utilizationRate) =
            cdxUsdIInterestRateStrategy.getCurrentInterestRates();
        console2.log("currentVariableBorrowRate: ", currentVariableBorrowRate);

        uint256 optimalStablePoolReserveUtilization =
            cdxUsdIInterestRateStrategy._optimalStablePoolReserveUtilization();

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
                Strings.toString(currentVariableBorrowRate),
                ",",
                Strings.toString(optimalStablePoolReserveUtilization)
            )
        );
        vm.writeLine(path, data);
    }

    function fixture_simulateBalancesChange(
        uint256[][] memory balances,
        uint256[] memory durations,
        string memory path,
        address tokenToSimulate
    ) internal {
        require(
            durations.length == balances.length,
            "balances length must be the same as durations length"
        );
        console2.log("balances length: ", balances.length);
        for (uint8 idx = 0; idx < balances.length; idx++) {
            console2.log("IDX: ->>> ", idx);
            console2.log("Balance[idx][0]: ->>> ", balances[idx][0]);
            balancerVaultMock.setBalancesForTokens(poolId, tokenAddresses, balances[idx]);
            logg(address(this), 0, address(tokenToSimulate), path);
            vm.warp(block.timestamp + durations[idx]);
            logg(address(this), 0, address(tokenToSimulate), path);
        }
    }

    function testPidWithErrGreaterThanZero() public {
        uint256[] memory durations = new uint256[](3);
        durations[0] = 1 days;
        durations[1] = 3 days;
        durations[2] = 3 days;

        uint256[][] memory balances = new uint256[][](3);
        for (uint8 idx = 0; idx < tokenAddresses.length; idx++) {
            balances[idx] = new uint256[](tokenAddresses.length);
            balances[0][idx] = INITIAL_BALANCE * 10 ** ERC20Mock(tokenAddresses[idx]).decimals();
        }

        console2.log(balances[0][0]);

        balancerVaultMock.setBalancesForTokens(poolId, tokenAddresses, balances[0]);
        vm.warp(block.timestamp + durations[0]);

        balances[1][0] = 1000 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[1][1] = 800 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[1][2] = 1200 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        balances[2][0] = 900 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[2][1] = 1100 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[2][2] = 1000 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        fixture_simulateBalancesChange(balances, durations, path1, address(cdxUSD));
    }

    function testPidWithErrLessThanZero() public {
        uint256[] memory durations = new uint256[](3);
        durations[0] = 1 days;
        durations[1] = 3 days;
        durations[2] = 3 days;

        uint256[][] memory balances = new uint256[][](3);
        for (uint8 idx = 0; idx < tokenAddresses.length; idx++) {
            balances[idx] = new uint256[](tokenAddresses.length);
            balances[0][idx] = INITIAL_BALANCE * 10 ** ERC20Mock(tokenAddresses[idx]).decimals();
        }

        balancerVaultMock.setBalancesForTokens(poolId, tokenAddresses, balances[0]);
        vm.warp(block.timestamp + durations[0]);

        balances[1][0] = 2000 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[1][1] = 500 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[1][2] = 500 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        balances[2][0] = 1000 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[2][1] = 1000 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[2][2] = 1000 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        fixture_simulateBalancesChange(balances, durations, path2, address(cdxUSD));
    }

    function testPidMixed1() public {
        uint256[] memory durations = new uint256[](5);
        durations[0] = 1 days;
        durations[1] = 6 days;
        durations[2] = 1 days;
        durations[3] = 3 days;
        durations[4] = 1 days;

        uint256[][] memory balances = new uint256[][](5);
        console2.log("Creating balances...");
        for (uint8 idx = 0; idx < 5; idx++) {
            balances[idx] = new uint256[](tokenAddresses.length);
        }
        console2.log("Initializing balances...");
        for (uint8 idx = 0; idx < tokenAddresses.length; idx++) {
            balances[0][idx] = INITIAL_BALANCE * 10 ** ERC20Mock(tokenAddresses[idx]).decimals();
        }

        console2.log("Setting balances...");
        balancerVaultMock.setBalancesForTokens(poolId, tokenAddresses, balances[0]);
        vm.warp(block.timestamp + durations[0]);

        balances[1][0] = 750 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[1][1] = 1000 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[1][2] = 1250 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        balances[2][0] = 1000 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[2][1] = 1000 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[2][2] = 1000 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        balances[3][0] = 2000 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[3][1] = 500 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[3][2] = 500 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        balances[4][0] = 1000 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[4][1] = 1000 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[4][2] = 1000 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        fixture_simulateBalancesChange(balances, durations, path3, address(cdxUSD));
    }

    function testPidMixed2() public {
        uint256[] memory durations = new uint256[](5);
        durations[0] = 1 days;
        durations[1] = 6 days;
        durations[2] = 1 days;
        durations[3] = 6 days;
        durations[4] = 1 days;

        uint256[][] memory balances = new uint256[][](5);
        console2.log("Creating balances...");
        for (uint8 idx = 0; idx < 5; idx++) {
            balances[idx] = new uint256[](tokenAddresses.length);
        }
        console2.log("Initializing balances...");
        for (uint8 idx = 0; idx < tokenAddresses.length; idx++) {
            balances[0][idx] = INITIAL_BALANCE * 10 ** ERC20Mock(tokenAddresses[idx]).decimals();
        }

        console2.log("Setting balances...");
        balancerVaultMock.setBalancesForTokens(poolId, tokenAddresses, balances[0]);
        vm.warp(block.timestamp + durations[0]);

        balances[1][0] = 750 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[1][1] = 1000 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[1][2] = 1250 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        balances[2][0] = 1000 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[2][1] = 1000 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[2][2] = 1000 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        balances[3][0] = 1250 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[3][1] = 1000 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[3][2] = 750 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        balances[4][0] = 1000 * 10 ** ERC20Mock(tokenAddresses[0]).decimals();
        balances[4][1] = 1000 * 10 ** ERC20Mock(tokenAddresses[1]).decimals();
        balances[4][2] = 1000 * 10 ** ERC20Mock(tokenAddresses[2]).decimals();

        fixture_simulateBalancesChange(balances, durations, path4, address(cdxUSD));
    }
}
