//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {FundMe} from "../../src/FundMe.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Handler} from "./Handler.t.sol";
import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract FundMeInvariantTest is StdInvariant, Test {
    FundMe public fundMe;
    Handler public handler;

    address FEE_RECIPIENT = makeAddr("feeRecipient");

    uint256 constant GOAL = 5 ether;
    uint256 constant PLATFORM_FEE_BPS = 200;
    uint256 constant REFUND_FEE_BPS = 100;

    uint8 constant DECIMALS = 8;
    int256 constant ETHPRICE = 2000e8;

    function setUp() external {
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, ETHPRICE);
        fundMe = new FundMe(address(mockPriceFeed), GOAL, FEE_RECIPIENT, PLATFORM_FEE_BPS, REFUND_FEE_BPS);
        handler = new Handler(fundMe);
        targetContract(address(handler));
    }

    function invariant_contractBalanceMatchesHandler() public view {
        assertEq(address(fundMe).balance, handler.totalFunded());
    }

    function invariant_FeesAccumulateCorrectly() public view {
        uint256 contractFees = fundMe.getPlatformFeesCollected();

        assertEq(contractFees, handler.totalPlatformFees());
    }

    function invariant_NoNegativeAccounting() public view {
        assertGe(handler.totalFunded(), 0);
        assertGe(handler.totalWithdrawn(), 0);
        assertGe(handler.totalPlatformFees(), 0);
    }

    function invariant_WithdrawNeverExceedsFunding() public view {
        assertLe(handler.totalWithdrawn(), handler.totalFunded() + handler.totalWithdrawn());
    }

    function invariant_UserBalancesAreValid() public view {
        address user1 = handler.users(0);
        address user2 = handler.users(1);
        address user3 = handler.users(2);

        assertGe(handler.userBalances(user1), 0);
        assertGe(handler.userBalances(user2), 0);
        assertGe(handler.userBalances(user3), 0);
    }

    function invariant_ContractBalanceNeverNegative() public view {
        assertGe(address(fundMe).balance, 0);
    }

    function invariant_ValueConservation() public view {
        uint256 contractBalance = address(fundMe).balance;

        uint256 totalOut = handler.totalWithdrawn() + handler.totalPlatformFees();

        uint256 totalIn = handler.totalFunded() + totalOut;

        assertEq(contractBalance + totalOut, totalIn);
    }

    function invariant_RefundAccountingMatches() public view {
        address user1 = handler.users(0);
        address user2 = handler.users(1);
        address user3 = handler.users(2);

        uint256 totalRefunded =
            handler.totalRefunded(user1) + handler.totalRefunded(user2) + handler.totalRefunded(user3);

        assertGe(handler.totalFunded(), 0);
        assertGe(totalRefunded, 0);
    }

    function invariant_SystemIntegrity() public view {
        invariant_contractBalanceMatchesHandler();
        invariant_FeesAccumulateCorrectly();
        invariant_ValueConservation();
        invariant_WithdrawNeverExceedsFunding();
    }

    function invariant_SumOfUserBalancesMatches() public view {
        uint256 sum;

        for (uint256 i = 0; i < handler.usersLength(); i++) {
            sum += handler.userBalances(handler.users(i));
        }

        assertEq(sum, handler.totalFunded());
    }
}
