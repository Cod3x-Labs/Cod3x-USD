// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import "lib/createx/src/CreateX.sol";

// cdxUSD salt   = 0x3d0c000adf317206fa4a3201a8f8c926ef394fad0047c74b092069a800a5ed54
// Deployer salt = 0x3d0c000adf317206fa4a3201a8f8c926ef394fad00a98c721b778d1401b27a21
contract Constants {
    /// all chains
    CreateX public constant createx = CreateX(address(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed)); // all chains
    address public constant cdxUsd = address(0xC0D3700000987C99b3C9009069E4f8413fD22330);
    address public constant deployer = address(0x3d0C000adF317206fA4A3201a8F8c926EF394fad);
    address public constant timelock = address(0xc0D3700924301AC384E5Eae3272E08220752DE3D);
    address public constant multisignAdmin = address(0xfEfcb2fb19b9A70B30646Fdc1A0860Eb12F7ff8b); // 3/X
    address public constant multisignGuardian = address(0x0D1d0f89cb988678B37FD5b5c6C1A5bBdc55f8ba); // 1/X

    address public admin;
    uint32 public eid;
    address public endpoint;
    bool public isMainnet;

    constructor() {
        // Mainnet : Ethereum
        if (block.chainid == 1) {
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

        if (isMainnet) {
            // admin = address(0);
            endpoint = address(0x1a44076050125825900e736c501f859c50fE728c);
        } else {
            // admin = address(0x92Cd849801A467098cDA7CD36756fbFE8A30A036);
            endpoint = address(0x6EDCE65403992e310A62460808c4b910D972f10f);
        }
    }
}
