// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/console2.sol";
import {ILendingPoolAddressesProvider} from
    "../lib/Cod3x-Lend/contracts/interfaces/ILendingPoolAddressesProvider.sol";

struct ExtContractsForConfiguration {
    address treasury;
    address rewarder;
    address oracle;
    address lendingPoolConfigurator;
    address lendingPoolAddressesProvider;
    address aTokenImpl;
    address variableDebtTokenImpl;
    address interestStrat;
}

struct PoolReserversConfig {
    bool borrowingEnabled;
    uint256 reserveFactor;
    bool reserveType;
}

struct BalancerContracts {
    address stablePoolFactory;
    address balRouter;
    address payable balVault;
}
// cdxUSD salt   = 0x3d0c000adf317206fa4a3201a8f8c926ef394fad0047c74b092069a800a5ed54
// Deployer salt = 0x3d0c000adf317206fa4a3201a8f8c926ef394fad00a98c721b778d1401b27a21

contract DeploymentConstants {
    /// all chains
    address public constant createx = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed; // all chains
    address public constant cdxUsd = 0xC0D3700000987C99b3C9009069E4f8413fD22330;
    address public constant deployer = 0xF29dA3595351dBFd0D647857C46F8D63Fc2e68C5;
    address public constant timelock = 0xc0D3700924301AC384E5Eae3272E08220752DE3D;
    address public constant multisignAdmin = 0xfEfcb2fb19b9A70B30646Fdc1A0860Eb12F7ff8b; // 3/X
    address public constant multisignGuardian = 0x0D1d0f89cb988678B37FD5b5c6C1A5bBdc55f8ba; // 1/X

    /// specific chains
    //// cod3x lend
    /// ETH
    address public constant TREASURY = address(0x5); // tmp
    address public constant REWARDER = address(0);
    address public constant LENDING_POOL = address(0);
    address public constant LENDING_POOL_ADDRESSES_PROVIDER = address(0);
    address public constant MINI_POOL_ADDRESSES_PROVIDER = address(0);
    address public constant ORACLE = address(0);

    /// BASE
    address public constant BASE_TREASURY = address(0x5); // tmp
    address public constant BASE_REWARDER = address(0);
    address public constant BASE_LENDING_POOL = 0x360996dA4E66f6282a142c8F86120F1adFf8Dd26;
    address public constant BASE_LENDING_POOL_ADDRESSES_PROVIDER =
        0xcc254E7f33B2f4b3534278DF237d21b4b71b444e;
    address public constant BASE_MINI_POOL_ADDRESSES_PROVIDER =
        0x5caB34F15b0a3d945FDaf21Cfd4F883BBF844b59;
    address public constant BASE_ORACLE = 0xe0413f5Feeb5EA370AbD6095DDf14D84871139Ab;

    // balancer V3
    ///ETH
    address public constant STABLE_POOL_FACTORY = 0x5B42eC6D40f7B7965BE5308c70e2603c0281C1E9;
    address public constant BAL_ROUTER = 0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC;
    address public constant BAL_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant STABLE_POOL_FACTORY_V3 = 0xB9d01CA61b9C181dA1051bFDd28e1097e920AB14;
    address public constant BAL_ROUTER_V3 = 0xAE563E3f8219521950555F5962419C8919758Ea2;
    address public constant BAL_VAULT_V3 = 0xbA1333333333a1BA1108E8412f11850A5C319bA9;
    /// BASE
    address public constant BASE_STABLE_POOL_FACTORY = 0xC49Ca921c4CD1117162eAEEc0ee969649997950c;
    address public constant BASE_BAL_ROUTER = 0x3f170631ed9821Ca51A59D996aB095162438DC10;
    address public constant BASE_BAL_VAULT = 0xbA1333333333a1BA1108E8412f11850A5C319bA9;

    /// tokens
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant BASE_WETH = 0x4200000000000000000000000000000000000006;
    address public constant BASE_WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    address public constant BASE_DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;

    // address public balancerContracts.stablePoolFactory =
    //     address(0xB9d01CA61b9C181dA1051bFDd28e1097e920AB14);
    // address payable public vaultV3 = payable(0xbA1333333333a1BA1108E8412f11850A5C319bA9);
    // address public routerV3 = address(0xAE563E3f8219521950555F5962419C8919758Ea2);

    ExtContractsForConfiguration public extContracts;
    PoolReserversConfig public poolReserversConfig;
    BalancerContracts public balancerContracts;

    address public weth;
    address public wbtc;
    address public dai;
    // address public balancerContracts.stablePoolFactory;
    // address payable public vaultV3;
    // address public routerV3;

    address public admin;
    uint32 public eid;
    address public endpoint;
    bool public isMainnet;

    constructor() {
        console2.log("SENDER: ", msg.sender);
        // Mainnet : Ethereum
        if (block.chainid == 1) {
            console2.log("-------- Mainnet ---------");
            // Cod3xLend
            extContracts.treasury = TREASURY;
            extContracts.rewarder = REWARDER;
            extContracts.oracle = ORACLE;
            extContracts.lendingPoolConfigurator = ILendingPoolAddressesProvider(
                LENDING_POOL_ADDRESSES_PROVIDER
            ).getLendingPoolConfigurator();
            extContracts.lendingPoolAddressesProvider = LENDING_POOL_ADDRESSES_PROVIDER;
            // extContracts.miniPoolAddressesProvider = MINI_POOL_ADDRESSES_PROVIDER;
            // extContracts.aTokenImpl = address(0);
            // extContracts.variableDebtTokenImpl = address(0);
            // extContracts.interestStrat = address(0);

            // Balancer
            // V2
            // balancerContracts.stablePoolFactory = STABLE_POOL_FACTORY;
            // balancerContracts.balVault = payable(BAL_VAULT);
            // balancerContracts.balRouter = BAL_ROUTER;

            // V3
            balancerContracts.stablePoolFactory = STABLE_POOL_FACTORY_V3;
            balancerContracts.balVault = payable(BAL_VAULT_V3);
            balancerContracts.balRouter = BAL_ROUTER_V3;

            // Tokens
            weth = WETH;
            wbtc = WBTC;
            dai = DAI;

            //Settings
            eid = 30101;
            isMainnet = true;
        }
        // Mainnet : Arbitrum
        if (block.chainid == 42161) {
            eid = 30110;
            isMainnet = true;
        }
        // Mainnet : Base
        if (block.chainid == 8453) {
            console2.log("-------- Base Mainnet ---------");
            // Cod3xLend
            extContracts.treasury = BASE_TREASURY;
            extContracts.rewarder = BASE_REWARDER;
            extContracts.oracle = BASE_ORACLE;
            extContracts.lendingPoolConfigurator = ILendingPoolAddressesProvider(
                BASE_LENDING_POOL_ADDRESSES_PROVIDER
            ).getLendingPoolConfigurator();
            extContracts.lendingPoolAddressesProvider = BASE_LENDING_POOL_ADDRESSES_PROVIDER;
            // extContracts.lendingPool = BASE_LENDING_POOL;
            // extContracts.miniPoolAddressesProvider = BASE_MINI_POOL_ADDRESSES_PROVIDER;
            // extContracts.aTokenImpl = address(0);
            // extContracts.variableDebtTokenImpl = address(0);
            // extContracts.interestStrat = address(0);

            // Balancer
            // V2
            // balancerContracts.stablePoolFactory = BASE_STABLE_POOL_FACTORY;
            // balancerContracts.balVault = payable(BASE_BAL_VAULT);
            // balancerContracts.balRouter = BASE_BAL_ROUTER;

            // V3
            balancerContracts.stablePoolFactory = BASE_STABLE_POOL_FACTORY;
            balancerContracts.balVault = payable(BASE_BAL_VAULT);
            balancerContracts.balRouter = BASE_BAL_ROUTER;

            // Tokens
            weth = BASE_WETH;
            wbtc = BASE_WBTC;
            dai = BASE_DAI;

            //Settings
            eid = 30184;
            isMainnet = true;
        }
        // Testnet : Sepolia Ethereum
        else if (block.chainid == 11155111) {
            eid = 40161;
            isMainnet = false;
        }
        // Testnet : Sepolia Arbitrum
        else if (block.chainid == 421614) {
            eid = 40231;
            isMainnet = false;
        }
        // Testnet : Polygon Amoy
        else if (block.chainid == 80002) {
            eid = 40267;
            isMainnet = false;
        }
        // Testnet : Sepolia Base
        else if (block.chainid == 84532) {
            console2.log("-------- Base Testnet ---------");

            // // Cod3xLend
            // extContracts.treasury = BASE_TREASURY;
            // extContracts.rewarder = BASE_REWARDER;
            // extContracts.oracle = BASE_ORACLE;
            // extContracts.lendingPoolConfigurator = ILendingPoolAddressesProvider(
            //     BASE_LENDING_POOL_ADDRESSES_PROVIDER
            // ).getLendingPoolConfigurator();
            // extContracts.lendingPoolAddressesProvider = BASE_LENDING_POOL_ADDRESSES_PROVIDER;
            // // extContracts.lendingPool = BASE_LENDING_POOL;
            // // extContracts.miniPoolAddressesProvider = BASE_MINI_POOL_ADDRESSES_PROVIDER;
            // // extContracts.aTokenImpl = address(0);
            // // extContracts.variableDebtTokenImpl = address(0);
            // // extContracts.interestStrat = address(0);

            // Balancer
            // V2
            // balancerContracts.stablePoolFactory = BASE_STABLE_POOL_FACTORY;
            // balancerContracts.balVault = payable(BASE_BAL_VAULT);
            // balancerContracts.balRouter = BASE_BAL_ROUTER;

            // // V3
            // balancerContracts.stablePoolFactory = BASE_STABLE_POOL_FACTORY;
            // balancerContracts.balVault = payable(BASE_BAL_VAULT);
            // balancerContracts.balRouter = BASE_BAL_ROUTER;

            // // Tokens
            // weth = BASE_WETH;
            // wbtc = BASE_WBTC;
            // dai = BASE_DAI;

            eid = 40284;
            isMainnet = false;
        } else {
            revert("Unsupported network");
        }

        if (isMainnet) {
            // admin = address(0);
            endpoint = address(0x1a44076050125825900e736c501f859c50fE728c);
        } else {
            // admin = address(0x92Cd849801A467098cDA7CD36756fbFE8A30A036);
            endpoint = address(0x6EDCE65403992e310A62460808c4b910D972f10f);
        }
        console2.log("StablePool : :::: ::: : ", balancerContracts.stablePoolFactory);
    }
}
