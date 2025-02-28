// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

/**
 * @title CdxUsdOracle
 * @notice Price feed for CdxUSD (USD denominated)
 * @dev Price fixed at 1 USD, Chainlink format with 8 decimals
 * @author Cod3x - Beirao
 */
contract CdxUsdOracle {
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
     * @notice Returns data about the latest price round
     * @dev All values except answer are hardcoded to 0 since price is fixed
     * @return roundId The round ID of this price update
     * @return answer The price of CdxUSD (fixed at 1 USD with 8 decimals)
     * @return startedAt The timestamp when this price update started
     * @return updatedAt The timestamp when this price was last updated
     * @return answeredInRound Deprecated - Previously used for multi-round answers
     */
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, CDXUSD_PRICE, 1, block.timestamp, 0);
    }

    /**
     * @notice Returns the number of decimals the price is formatted with
     * @return The number of decimals
     */
    function decimals() external pure returns (uint8) {
        return 8;
    }
}
