// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBalancerMinter {
    function mint(address gauge) external returns (uint256);
    function mintMany(address[] calldata gauges) external returns (uint256);
    function mintManyFor(address[] calldata gauges, address user) external returns (uint256);
}
