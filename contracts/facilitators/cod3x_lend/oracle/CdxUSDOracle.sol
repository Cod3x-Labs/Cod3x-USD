// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

/**
 * @title CdxUsdOracle
 * @notice A price feed oracle for CdxUSD that maintains a fixed 1:1 peg to USD.
 * @dev Implements a Chainlink-compatible interface with 8 decimal precision. The price is hardcoded
 * to 1 USD.
 * @author Cod3x - Beirao
 */
contract CdxUsdOracle {
    /// @dev The fixed price of 1 CdxUSD in USD, with 8 decimal precision (1.00000000).
    int256 public constant CDXUSD_PRICE = 1e8;

    /**
     * @notice Gets the current CdxUSD/USD price.
     * @dev Returns the fixed 1 USD price with 8 decimal precision. This price never changes.
     * @return The fixed price of 1 CdxUSD in USD terms, formatted with 8 decimals.
     */
    function latestAnswer() external pure returns (int256) {
        return CDXUSD_PRICE;
    }

    /**
     * @notice Gets the latest round data in Chainlink oracle format.
     * @dev Most fields are fixed values since price never changes. Only updatedAt varies with time.
     * @return roundId Always returns 1 since price is static.
     * @return answer The fixed CdxUSD price of 1 USD with 8 decimals.
     * @return startedAt Always returns 1 since rounds are not tracked.
     * @return updatedAt Current block timestamp to maintain Chainlink compatibility.
     * @return answeredInRound Always returns 0 since historical rounds are not tracked.
     */
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, CDXUSD_PRICE, 1, block.timestamp, 0);
    }

    /**
     * @notice Gets the number of decimal places in the price feed.
     * @dev Fixed at 8 decimals to match Chainlink's USD price feed format.
     * @return The number of decimal places (8).
     */
    function decimals() external pure returns (uint8) {
        return 8;
    }
}
