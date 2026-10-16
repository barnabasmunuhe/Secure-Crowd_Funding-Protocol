// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Why is this a library and not abstract?
// Why not an interface?
library PriceConverter {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error PriceConverter__InvalidPriceData(int256 answer);
    error PriceConverter__StalePrice(uint256 updatedAt);
    error PriceConverter__IncompleteRound(uint80 roundId, uint80 answeredInRound);

    /// @dev Max age of a Chainlink answer before it is considered stale.
    uint256 internal constant STALENESS_THRESHOLD = 1 hours;

    // We could make this public, but then we'd have to deploy it
    function getPrice(AggregatorV3Interface priceFeed) internal view returns (uint256) {
        // Sepolia ETH / USD Address
        // https://docs.chain.link/data-feeds/price-feeds/addresses

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        // rejects non +ve answers
        if (answer <= 0) revert PriceConverter__InvalidPriceData(answer);

        // reject zero/ stale timestamps
        if(updatedAt == 0 || block.timestamp - updatedAt > STALENESS_THRESHOLD) {
            revert PriceConverter__StalePrice(updatedAt);
        }

        // reject incomplete rounds
        if(answeredInRound < roundId) {
            revert PriceConverter__IncompleteRound(roundId, answeredInRound);
        }
        return uint256(answer * 1e10); // Chainlink ETH/USD price data returns the price in 8 decimal places
            // so multiplying by 10^10 to get it to 18 decimal places, which is the standard for ETH amounts in Solidity.
    }

    /**
     * @notice Converts a wei amount to its USD value (18 decimals).
     */

    function getConversionRate(uint256 ethAmount, AggregatorV3Interface priceFeed) internal view returns (uint256) {
        uint256 ethPrice = getPrice(priceFeed);
        uint256 ethAmountInUsd = (ethPrice * ethAmount) / 1e18;
        // the actual ETH/USD conversion rate, after adjusting the extra 0s.
        return ethAmountInUsd;
    }
}
