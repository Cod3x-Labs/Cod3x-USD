// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import "lib/createx/src/CreateX.sol";

contract Constants {
    /// all chain
    CreateX public constant createx = CreateX(address(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed)); // all chain

    address public cdxUsdTestNet = address(0x82b3bcF54E2697BCad3fF3a8bb517064970D7345);
    address public admin = address(0x92Cd849801A467098cDA7CD36756fbFE8A30A036); // testnet address

    uint32 public eid;
    address public endpoint;

    constructor() {
        
        // Mainnet : Ethereum
        if (block.chainid == 1) {
            eid = 30101;
            endpoint = address(0x1a44076050125825900e736c501f859c50fE728c);
        }

        // Testnet : Sepolia Ethereum
        else if (block.chainid == 11155111) {
            eid = 40161;
            endpoint = address(0x6EDCE65403992e310A62460808c4b910D972f10f);
        }

        // Testnet : Sepolia Arbitrum
        else if (block.chainid == 421614) {
            eid = 40231;
            endpoint = address(0x6EDCE65403992e310A62460808c4b910D972f10f);
        }

        // Testnet : Polygon Amoy
        else if (block.chainid == 80002) {
            eid = 40267;
            endpoint = address(0x6EDCE65403992e310A62460808c4b910D972f10f);
        }
    }
}