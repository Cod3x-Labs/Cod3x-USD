// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IFacilitator
 * @author Cod3X Labs - Beirao
 * @notice Defines the behavior of a Gho Facilitator
 * Reference: https://github.com/aave/gho-core/blob/main/src/contracts/gho/interfaces/IGhoFacilitator.sol
 */
interface IFacilitator {
    /**
     * @dev Emitted when fees are distributed to the GhoTreasury
     * @param treasury The address of the treasury
     * @param asset The address of the asset transferred to the treasury
     * @param amount The amount of the asset transferred to the treasury
     */
    event FeesDistributedToTreasury(
        address indexed treasury, address indexed asset, uint256 amount
    );

    /**
     * @dev Emitted when Gho Treasury address is updated
     * @param oldTreasury The address of the old GhoTreasury contract
     * @param newTreasury The address of the new GhoTreasury contract
     */
    event GhoTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /**
     * @notice Distribute fees to the GhoTreasury
     */
    function distributeFeesToTreasury() external;

    /**
     * @notice Updates the address of the Gho Treasury
     * @dev WARNING: The GhoTreasury is where revenue fees are sent to. Update carefully
     * @param newGhoTreasury The address of the GhoTreasury
     */
    function updateGhoTreasury(address newGhoTreasury) external;

    /**
     * @notice Returns the address of the Gho Treasury
     * @return The address of the GhoTreasury contract
     */
    function getGhoTreasury() external view returns (address);
}
