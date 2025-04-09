// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @title ICdxUSDFacilitators
 * @author Cod3x - Beirao
 * @notice Defines the behavior of a CdxUSD Facilitator
 */
interface ICdxUSDFacilitators {
    /// Events
    event FeesDistributedToTreasury(
        address indexed treasury, address indexed asset, uint256 amount
    );

    /**
     * @notice Distribute fees to treasury.
     */
    function distributeFeesToTreasury() external;
}
