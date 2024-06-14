// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingModuleDeployer is Ownable {
    constructor() Ownable(msg.sender) {}

    function deploy() public {}
}
