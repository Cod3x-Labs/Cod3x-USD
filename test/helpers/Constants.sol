// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "test/helpers/interfaces/ICreateX.sol";
import "script/DeploymentConstants.s.sol";
import "forge-std/console2.sol";

contract Constants is DeploymentConstants {
// /// specific chains
// //// cod3x lend
// address public constant BASE_REWARDER = address(0);
// address public constant BASE_LENDING_POOL = 0x360996dA4E66f6282a142c8F86120F1adFf8Dd26;
// address public constant BASE_LENDING_POOL_ADDRESSES_PROVIDER =
//     0xcc254E7f33B2f4b3534278DF237d21b4b71b444e;
// address public constant BASE_MINI_POOL_ADDRESSES_PROVIDER =
//     0x5caB34F15b0a3d945FDaf21Cfd4F883BBF844b59;
// address public constant BASE_ORACLE = 0xe0413f5Feeb5EA370AbD6095DDf14D84871139Ab;

// /// tokens
// address public constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
// address public constant BASE_WETH = 0x4200000000000000000000000000000000000006;

// // balancer V3
// address public constant BASE_STABLE_POOL_FACTORY = 0xC49Ca921c4CD1117162eAEEc0ee969649997950c;
// address public constant BASE_BAL_ROUTER = 0x3f170631ed9821Ca51A59D996aB095162438DC10;
// address public constant BASE_BAL_VAULT = 0xbA1333333333a1BA1108E8412f11850A5C319bA9;

// address public weth;
// address public wbtc;
// address public dai;
// // address public usdc;
// // V2
// address public composableStablePoolFactory;
// address public vault;
// address public gaugeFactory;

// // V3
// address public balancerContracts.stablePoolFactory;
// address payable public vaultV3;
// address public routerV3;

// /// all chains
// address public constant createx = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed; // all chains
// address public constant cdxUsd = address(0xC0D3700000987C99b3C9009069E4f8413fD22330);
// address public constant deployer = address(0x3d0C000adF317206fA4A3201a8F8c926EF394fad);
// address public constant timelock = address(0xc0D3700924301AC384E5Eae3272E08220752DE3D);
// address public constant multisignAdmin = address(0xfEfcb2fb19b9A70B30646Fdc1A0860Eb12F7ff8b); // 3/X
// address public constant multisignGuardian = address(0x0D1d0f89cb988678B37FD5b5c6C1A5bBdc55f8ba); // 1/X
// address public constant treasury = address(0x5); // tmp

// constructor() {
//     // Mainnet : Ethereum
//     if (block.chainid == 1) {
//         // V2
//         weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
//         wbtc = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
//         dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
//         composableStablePoolFactory = address(0x5B42eC6D40f7B7965BE5308c70e2603c0281C1E9);
//         vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
//         gaugeFactory = address(0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC);

//         // V3
//         balancerContracts.stablePoolFactory = address(0xB9d01CA61b9C181dA1051bFDd28e1097e920AB14);
//         vaultV3 = payable(0xbA1333333333a1BA1108E8412f11850A5C319bA9);
//         routerV3 = address(0xAE563E3f8219521950555F5962419C8919758Ea2);
//     }
//     // Mainnet : Arbitrum
//     if (block.chainid == 42161) {}
//     // Mainnet : Base
//     if (block.chainid == 8453) {
//         // V2
//         weth = BASE_WETH;
//         // wbtc = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
//         // dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
//         // usdc = BASE_USDC;
//         // composableStablePoolFactory = address(0x5B42eC6D40f7B7965BE5308c70e2603c0281C1E9);
//         // vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
//         // gaugeFactory = address(0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC);

//         // V3
//         balancerContracts.stablePoolFactory = BASE_STABLE_POOL_FACTORY;
//         vaultV3 = payable(BASE_BAL_VAULT);
//         routerV3 = BASE_BAL_ROUTER;
//     }
//     // Testnet : Sepolia Ethereum
//     else if (block.chainid == 11155111) {}
//     // Testnet : Sepolia Arbitrum
//     else if (block.chainid == 421614) {}
//     // Testnet : Polygon Amoy
//     else if (block.chainid == 80002) {}
//     // Testnet : Sepolia Base
//     else if (block.chainid == 84532) {
//         // V2
//         weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
//         wbtc = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
//         dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
//         composableStablePoolFactory = address(0x5B42eC6D40f7B7965BE5308c70e2603c0281C1E9);
//         vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
//         gaugeFactory = address(0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC);

//         // V3
//         balancerContracts.stablePoolFactory = address(0xB9d01CA61b9C181dA1051bFDd28e1097e920AB14);
//         vaultV3 = payable(0xbA1333333333a1BA1108E8412f11850A5C319bA9);
//         routerV3 = address(0xAE563E3f8219521950555F5962419C8919758Ea2);
//     }
// }
}
