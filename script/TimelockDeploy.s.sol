// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import "lib/createx/src/CreateX.sol";
import "./Constants.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

contract TimelockDeploy is Script, Constants {
    uint256 minDelay = 1 days;
    address[] proposers = [multisignAdmin]; // Multisign 3/X
    address[] executors = [multisignGuardian]; // Multisign 1/X

    function setUp() public {}

    function run() public {
        bytes memory args = abi.encode(minDelay, proposers, executors, multisignAdmin);
        bytes memory cachedInitCode = abi.encodePacked(type(TimelockController).creationCode, args);

        vm.broadcast();
        address l = createx.deployCreate3{value: 0}(
            bytes32(0x3d0c000adf317206fa4a3201a8f8c926ef394fad00a98c721b778d1401b27a21),
            cachedInitCode
        );

        console2.log("Chain id: ", block.chainid);
        console2.log("Timelock address: ", l);
    }
}
