// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FundMe} from "../../src/FundMe.sol";
import {FundMeHandler} from "./FundMeHandler.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract FundMeInvariantTest is StdInvariant, Test {
    FundMe public fundMe;
    FundMeHandler public handler;

    address public feeRecipient;

    uint256 public constant GOAL_USD = 10_000e18;
    uint256 public constant MINIMUM_USD = 5e18;

    uint256 public constant PLATFORM_FEE_BPS = 200;
    uint256 public constant REFUND_FEE_BPS = 100;

    uint256 public constant DURATION = 60;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_PRICE = 2_000e8;

    function setUp() external {
        // 1. Create a mock Chainlink price feed.
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, ETH_PRICE);

        // 2. Create the fee recipient.
        feeRecipient = makeAddr("feeRecipient");

        // 3. Deploy FundMe.
        fundMe = new FundMe(
            address(mockPriceFeed), MINIMUM_USD, GOAL_USD, feeRecipient, PLATFORM_FEE_BPS, REFUND_FEE_BPS, DURATION
        );

        // 4. Deploy the handler.
        handler = new FundMeHandler(fundMe);

        // 5. Tell Foundry to target the handler.
        targetContract(address(handler));
    }

    /*//////////////////////////////////////////////////////////////
                        HISTORICAL FUNDING
    //////////////////////////////////////////////////////////////*/

    function invariant_HistoricalFundingMatchesHandler() public view {
        assertEq(fundMe.getTotalAmountFunded(), handler.ghostTotalFunded());
    }

    /*//////////////////////////////////////////////////////////////
                        CONTRACT BALANCE
    //////////////////////////////////////////////////////////////*/

    function invariant_ContractBalanceIsCorrect() public view {
        uint256 totalFunded = handler.ghostTotalFunded();
        uint256 totalRefunded = handler.ghostTotalRefunded();
        uint256 totalWithdrawn = handler.ghostGrossWithdrawn();

        // Refunds cannot exceed historical funding.
        assertLe(totalRefunded, totalFunded);

        uint256 remainingFunds = totalFunded - totalRefunded;

        // Gross withdrawals cannot exceed remaining funds.
        assertLe(totalWithdrawn, remainingFunds);

        uint256 expectedBalance = remainingFunds - totalWithdrawn;

        assertEq(address(fundMe).balance, expectedBalance);
    }

    /*//////////////////////////////////////////////////////////////
                        PLATFORM FEE ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function invariant_FeesAccumulateCorrectly() public view {
        assertEq(fundMe.getPlatformFeesCollected(), handler.ghostTotalPlatformFees());
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    function invariant_OwnerPayoutMatchesHandler() public view {
        assertEq(fundMe.getTotalWithdrawnByOwner(), handler.ghostTotalOwnerPayout());
    }

    function invariant_WithdrawalsNeverExceedAvailableFunds() public view {
        uint256 totalFunded = handler.ghostTotalFunded();
        uint256 totalRefunded = handler.ghostTotalRefunded();
        uint256 totalWithdrawn = handler.ghostGrossWithdrawn();

        assertLe(totalRefunded, totalFunded);

        assertLe(totalWithdrawn, totalFunded - totalRefunded);
    }

    /*//////////////////////////////////////////////////////////////
                        USER ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function invariant_UserContributionsMatchHandler() public view {
        for (uint256 i; i < handler.usersLength(); i++) {
            address user = handler.getUser(i);

            assertEq(fundMe.getAddressToAmountFunded(user), handler.ghostOutstandingContribution(user));
        }
    }

    function invariant_SumOfOutstandingContributionsMatches() public view {
        uint256 totalOutstanding;

        for (uint256 i; i < handler.usersLength(); i++) {
            address user = handler.getUser(i);

            totalOutstanding += fundMe.getAddressToAmountFunded(user);
        }

        assertEq(totalOutstanding, handler.ghostTotalFunded() - handler.ghostTotalRefunded());
    }
}
