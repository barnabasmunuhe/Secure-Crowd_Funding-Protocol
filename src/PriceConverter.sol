// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title PriceConverter
/// @notice Converts ETH amounts to USD using a Chainlink ETH/USD price feed.
library PriceConverter {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error PriceConverter__InvalidPriceData(int256 answer);
    error PriceConverter__StalePrice(uint256 updatedAt);
    error PriceConverter__IncompleteRound(uint80 roundId, uint80 answeredInRound);

    /// @dev Max age of a Chainlink answer before it is considered stale.
    uint256 internal constant STALENESS_THRESHOLD = 1 hours;
    uint256 internal constant PRICE_FEED_DECIMALS = 8;
    uint256 internal constant TARGET_DECIMALS = 18;

    /**
     * @notice Returns the ETH/USD price scaled to 18 decimals.
     */
    function getPrice(AggregatorV3Interface priceFeed) internal view returns (uint256) {
        // Sepolia ETH / USD Address
        // https://docs.chain.link/data-feeds/price-feeds/addresses

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        // rejects non +ve answers
        if (answer <= 0) revert PriceConverter__InvalidPriceData(answer);

        // reject zero/ stale timestamps including future oracle timestamps
        if (updatedAt == 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > STALENESS_THRESHOLD) {
            revert PriceConverter__StalePrice(updatedAt);
        }

        // reject incomplete rounds
        if (answeredInRound < roundId) {
            revert PriceConverter__IncompleteRound(roundId, answeredInRound);
        }
        //forge-lint: disable-next-line(unsafe-typecast)
        return uint256(answer * int256(10 ** (TARGET_DECIMALS - PRICE_FEED_DECIMALS)));
    }

    /**
     * @notice Converts a wei-denominated ETH amount to USD, scaled to 18 decimals.
     */
    function getConversionRate(uint256 ethAmount, AggregatorV3Interface priceFeed) internal view returns (uint256) {
        return Math.mulDiv(getPrice(priceFeed), ethAmount, 1e18);
    }
}
