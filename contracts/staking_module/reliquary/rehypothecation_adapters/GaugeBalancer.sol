// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "contracts/interfaces/IReliquary.sol";
import "contracts/interfaces/IRehypothecation.sol";
import "contracts/interfaces/IBalancerGauge.sol";
import "contracts/interfaces/IBalancerMinter.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//! CAUTION: Don't use this contract blindly, make sure it's compatible with the gauge version
/**
 * @title GaugeBalancer
 * @notice Adapter contract for interacting with Balancer Gauges
 * @dev This contract allows the Reliquary to stake LP tokens in Balancer Gauges and claim rewards
 */
contract GaugeBalancer is IRehypothecation, Ownable {
    using SafeERC20 for IERC20;

    /// @dev Reference to the Reliquary contract
    IReliquary public immutable reliquary;

    /// @dev Reference to the Balancer Gauge contract
    IBalancerGauge public immutable gauge;

    /// @dev The LP token that will be staked in the gauge
    IERC20 public immutable token;

    /// @dev The BAL token contract
    IERC20 public immutable balToken;

    /// @dev Reference to the Balancer Minter contract for claiming BAL rewards
    IBalancerMinter public immutable balancerMinter;

    /// @dev Error for invalid addresses
    error GaugeBalancer__INVALID_ADDRESS();

    /**
     * @notice Initializes the GaugeBalancer contract
     * @param _reliquary Address of the Reliquary contract
     * @param _gauge Address of the Balancer Gauge
     * @param _token Address of the LP token to be staked
     * @param _balToken Address of the BAL token
     * @param _balancerMinter Address of the Balancer Minter contract
     */
    constructor(
        address _reliquary,
        address _gauge,
        address _token,
        address _balToken,
        address _balancerMinter
    ) Ownable(_reliquary) {
        if (
            _reliquary == address(0) || _gauge == address(0) || _token == address(0)
                || _balToken == address(0)
        ) revert GaugeBalancer__INVALID_ADDRESS();

        reliquary = IReliquary(_reliquary);
        gauge = IBalancerGauge(_gauge);
        token = IERC20(_token);
        balToken = IERC20(_balToken);
        balancerMinter = IBalancerMinter(_balancerMinter);

        // Approvals
        token.approve(_gauge, type(uint256).max);
    }

    /// ============= Externals =============

    /**
     * @notice Deposits LP tokens into the Balancer Gauge
     * @param _amt Amount of LP tokens to deposit
     * @dev Can only be called by the owner (Reliquary)
     */
    function deposit(uint256 _amt) external onlyOwner {
        token.safeTransferFrom(msg.sender, address(this), _amt);
        gauge.deposit(_amt);
    }

    /**
     * @notice Withdraws LP tokens from the Balancer Gauge
     * @param _amt Amount of LP tokens to withdraw
     * @dev Can only be called by the owner (Reliquary)
     */
    function withdraw(uint256 _amt) external onlyOwner {
        gauge.withdraw(_amt);
        token.safeTransfer(msg.sender, _amt);
    }

    /**
     * @notice Claims all available rewards from the gauge and BAL tokens from the minter
     * @param _receiver Address to receive the claimed rewards
     * @dev Can only be called by the owner (Reliquary)
     */
    function claim(address _receiver) external onlyOwner {
        // Claim rewards.
        gauge.claim_rewards();
        for (uint256 i = 0; i < gauge.reward_count(); i++) {
            IERC20 tokenToClaim_ = gauge.reward_tokens(i);
            uint256 amtToClaim_ = tokenToClaim_.balanceOf(address(this));
            if (amtToClaim_ != 0) tokenToClaim_.safeTransfer(_receiver, amtToClaim_);
        }

        // Mint BAL tokens.
        if (address(balancerMinter) != address(0)) {
            uint256 amtToMint_ = balancerMinter.mint(address(gauge));
            if (amtToMint_ != 0) balToken.safeTransfer(_receiver, amtToMint_);
        }
    }

    /// ============= Views =============

    /**
     * @notice Returns the current balance of LP tokens staked in the gauge
     * @return The amount of LP tokens staked
     */
    function balance() external returns (uint256) {
        return gauge.balanceOf(address(this));
    }
}
