// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IRehypothecation {
    function deposit(uint256 _amt) external;
    function withdraw(uint256 _amt) external;
    function claim() external;

    function balanceOf(address _add) external view returns (uint256);
    function getRewardTokens() external view returns (address[] memory);
}
