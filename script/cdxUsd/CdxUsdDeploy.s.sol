// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import "lib/createx/src/CreateX.sol";
import "../DeploymentConstants.s.sol";
import "contracts/tokens/CdxUSD.sol";

contract CdxUsdDeploy is Script, DeploymentConstants {
    string public name = "Cod3x USD";
    string public symbol = "cdxUSD";
    address public delegate = timelock; // testnet address
    address public treasury = multisignAdmin; // testnet address
    address public guardian = multisignGuardian; // testnet address

    function setUp() public {}

    function run() public {
        bytes memory args = abi.encode(name, symbol, endpoint, delegate, treasury, guardian);
        bytes memory cachedInitCode = abi.encodePacked(type(CdxUSD).creationCode, args);

        vm.broadcast();
        address l = CreateX(createx).deployCreate3{value: 0}(
            bytes32(0x3d0c000adf317206fa4a3201a8f8c926ef394fad0047c74b092069a800a5ed54),
            cachedInitCode
        );

        console2.log("Chain id: ", block.chainid);
        console2.log("CdxUSD address: ", l);
    }
}
