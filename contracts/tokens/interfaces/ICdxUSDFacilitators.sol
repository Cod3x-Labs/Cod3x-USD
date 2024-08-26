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
        address indexed cdxUsdTreasury, address indexed asset, uint256 amount
    );

    event CdxUsdTreasuryUpdated(
        address indexed oldCdxUsdTreasury, address indexed newCdxUsdTreasury
    );

    /**
     * @notice Distribute fees to treasury.
     */
    function distributeFeesToTreasury() external;

    /**
     * @notice Updates the address of the CdxUSD Treasury
     * @dev WARNING: The cdxUsdTreasury is where revenue fees are sent to. Update carefully
     * @param newcdxUsdTreasury The address of the cdxUsdTreasury
     */
    function updateCdxUsdTreasury(address newcdxUsdTreasury) external;

    /**
     * @notice Returns the address of the CdxUSD Treasury
     * @return The address of the cdxUsdTreasury contract
     */
    function getCdxUsdTreasury() external view returns (address);
}
