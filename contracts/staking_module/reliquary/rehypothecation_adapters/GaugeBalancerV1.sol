// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "../interfaces/IRehypothecation.sol";
import "../interfaces/IReliquary.sol";
import "../interfaces/IBalancerGauge.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev GaugeBalancerV1 is for Ethereum.
contract GaugeBalancerV1 is IRehypothecation, AccessControl {
    using SafeERC20 for IERC20;

    IReliquary public reliquary;
    IBalancerGauge public gauge;
    IERC20 public token;
    address[] public tokensToClaim;

    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant USER = keccak256("USER");

    constructor(
        address _reliquary,
        address _gauge,
        address _token,
        address _admin,
        address[] memory _tokensToClaim
    ) {
        reliquary = IReliquary(_reliquary);
        gauge = IBalancerGauge(_gauge);
        token = IERC20(_token);
        tokensToClaim = _tokensToClaim;

        // Approvals
        token.approve(_gauge, type(uint256).max);

        // Roles
        _grantRole(ADMIN, _reliquary);
        _grantRole(USER, _reliquary);
    }

    /// ============= Admin =============

    function setTokensToClaim(address[] memory _tokensToClaim) external onlyRole(ADMIN) {
        tokensToClaim = _tokensToClaim;
    }

    /// ============= Externals =============

    function deposit(uint256 _amt) external onlyRole(USER) {
        token.transferFrom(msg.sender, address(this), _amt);
        gauge.deposit(_amt);
    }

    function withdraw(uint256 _amt) external onlyRole(USER) {
        gauge.withdraw(_amt);
        token.transfer(msg.sender, _amt);
    }

    function claim(address _receiver) external onlyRole(USER) {
        // gauge.claim_rewards();
        // for (uint256 i = 0; i < tokensToClaim.length; i++) {
        //     address tokenToClaim_ = tokensToClaim[i];
        //     token.safeTransfer(_receiver, IERC20(tokenToClaim_).balanceOf(address(this)));
        // }
    }

    /// ============= Views =============

    function balance() external view returns (uint256) {}

    function getRewardTokens() external view returns (address[] memory) {
        return tokensToClaim;
    }
}
