// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @title CdxUSDOracle
 * @notice Price feed for CdxUSD (USD denominated)
 * @dev Price fixed at 1 USD, Chainlink format with 8 decimals
 * @author Cod3x - Beirao
 */
contract CdxUSDOracle {
    int256 public constant CDXUSD_PRICE = 1e8;

    /**
     * @notice Returns the price of a unit of CdxUSD (USD denominated)
     * @dev CdxUSD price is fixed at 1 USD
     * @return The price of a unit of CdxUSD (with 8 decimals)
     */
    function latestAnswer() external pure returns (int256) {
        return CDXUSD_PRICE;
    }

    /**
     * @notice Returns the number of decimals the price is formatted with
     * @return The number of decimals
     */
    function decimals() external pure returns (uint8) {
        return 8;
    }
}
