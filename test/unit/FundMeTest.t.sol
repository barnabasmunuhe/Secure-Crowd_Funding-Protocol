//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract FundMeTest is Test {
    FundMe fundMe;
    MockV3Aggregator mockPriceFeed;

    receive() external payable {}

    address USER = makeAddr("user");
    address USER2 = makeAddr("user2");
    address USER3 = makeAddr("user3");
    address FEE_RECIPIENT = makeAddr("feeRecipient");

    uint256 constant USER_STARTING_BALANCE = 10 ether;
    uint256 constant GOAL_USD = 10000e18;
    uint256 constant GOAL_ETH = 5 ether;

    uint256 constant MINIMUM_USD = 5e18;
    uint256 constant MINIMUM_ETH = 0.0025 ether;

    uint256 constant BPS = 10_000; // 100%
    uint256 constant PLATFORM_FEE_BPS = 200; //2%
    uint256 constant REFUND_FEE_BPS = 100; //1%
    uint256 constant DURATION = 60; //seconds
    uint8 constant DECIMALS = 8;
    int256 constant ETHPRICE = 2000e8; // $2000

    function setUp() external {
        mockPriceFeed = new MockV3Aggregator(DECIMALS, ETHPRICE); // 2000 USD with 8 decimals

        fundMe = new FundMe(
            address(mockPriceFeed), MINIMUM_USD, GOAL_USD, FEE_RECIPIENT, PLATFORM_FEE_BPS, REFUND_FEE_BPS, DURATION
        );
        vm.deal(USER, USER_STARTING_BALANCE);
        vm.deal(USER2, USER_STARTING_BALANCE);
        vm.deal(USER3, USER_STARTING_BALANCE);
    }

    modifier userFunded() {
        vm.prank(USER);
        fundMe.fund{value: MINIMUM_ETH}();
        _;
    }

    modifier fullGoalFunded() {
        vm.prank(USER);
        fundMe.fund{value: GOAL_ETH}();
        _;
    }

    // constructor function tests/General
    function testInitialStateIsActive() public view {
        assertEq(uint256(fundMe.getState()), 0); // ACTIVE
    }

    function testMinimumUsdIsSetCorrectly() public view {
        assertEq(fundMe.i_minimumUsd(), MINIMUM_USD);
    }

    function testOwnerIsSetCorrectly() public view {
        assertEq(fundMe.getOwner(), address(this));
    }

    function testGoalIsSetCorrectly() public view {
        assertEq(fundMe.i_goalUsd(), GOAL_USD);
    }

    function testFeeRecipientIsSetCorrectly() public view {
        assertEq(fundMe.i_feeRecipient(), FEE_RECIPIENT);
    }

    ///////////////////////////////////////////
    ///              FUNDING TESTS           ///
    ///////////////////////////////////////////
    function testPriceFeedAddressIsCorrect() public view {
        assertEq(fundMe.getPriceFeed(), address(mockPriceFeed));
    }

    function testFundFailsWithoutEnoughETH() public {
        vm.expectRevert(FundMe.FundMe__SpendMoreEth.selector);
        fundMe.fund(); //send 0 value
    }

    function testFundRevertsIfBelowMinimum() public {
        vm.prank(USER);

        vm.expectRevert(FundMe.FundMe__SpendMoreEth.selector); // MINIMUM_USD check
        fundMe.fund{value: 0.002 ether}(); // too small below $5
    }

    function testFundUpdatesFundedMapping() public userFunded {
        assertEq(fundMe.getAddressToAmountFunded(USER), MINIMUM_ETH);
    }

    function testAddsFunderToArrayOfFunders() public userFunded {
        assertEq(fundMe.getFunder(0), USER);
    }

    function testFundUpdatesTotalEthFunded() public userFunded {
        assertEq(fundMe.getTotalAmountFunded(), MINIMUM_ETH);
    }

    function testFundUpdatesTotalUsdFunded() public userFunded {
        assertEq(fundMe.getTotalAmountFundedUsd(), MINIMUM_USD);
    }

    function testMultipleFunders() public {
        vm.prank(USER);
        fundMe.fund{value: MINIMUM_ETH}();

        vm.prank(USER2);
        fundMe.fund{value: MINIMUM_ETH}();

        assertEq(fundMe.getFunder(0), USER);
        assertEq(fundMe.getFunder(1), USER2);
        assertEq(fundMe.getTotalAmountFunded(), 0.005 ether);
    }

    function testSameFunderIsNotAddedTwice() public {
        vm.prank(USER);
        fundMe.fund{value: 1 ether}();

        vm.prank(USER);
        fundMe.fund{value: 1 ether}();

        assertEq(fundMe.getFunder(0), USER);

        // There should be no second entry.
        vm.expectRevert();
        fundMe.getFunder(1);
    }

    function testGoalReachedChangesState() public {
        vm.prank(USER);
        fundMe.fund{value: GOAL_ETH}();

        assertEq(uint256(fundMe.getState()), 1); // SUCCESS
    }

    function testFundingAfterGoalReachedReverts() public {
        vm.prank(USER);
        fundMe.fund{value: GOAL_ETH}();

        vm.prank(USER2);
        vm.expectRevert(FundMe.FundMe__NotActive.selector);
        fundMe.fund{value: 1 ether}();
    }

    function testFundingAtExactDeadlineReverts() public {
        vm.warp(fundMe.i_deadline());

        vm.prank(USER2);
        vm.expectRevert(FundMe.FundMe__CampaignEnded.selector);
        fundMe.fund{value: 1 ether}();
    }

    function testFundingAfterDeadlineReverts() public {
        vm.warp(fundMe.i_deadline() + 1);

        vm.prank(USER);
        vm.expectRevert(FundMe.FundMe__CampaignEnded.selector);
        fundMe.fund{value: 1 ether}();
    }

    function testReceiveFunctionTriggersFund() public {
        vm.prank(USER3);
        (bool success,) = address(fundMe).call{value: 1 ether}(""); //USER3 didn't call fund() directly, but sent ETH to the contract address, which should trigger the receive function and fund the contract

        assertTrue(success);
        assertEq(fundMe.getAddressToAmountFunded(USER3), 1 ether);
    }

    function testFallbackFunctionTriggersFund() public {
        vm.prank(USER2);
        (bool success,) = address(fundMe).call{value: 2 ether}("0x1234"); // sending data that doesn't match any function signature should trigger the fallback function, which should also fund the contract

        assertTrue(success);
        assertEq(fundMe.getAddressToAmountFunded(USER2), 2 ether);
    }

    //     // function testFallbackReentrancyDoesNotBreakAccounting() public {
    //     // MaliciousFunder attacker = new MaliciousFunder(address(fundMe));

    //     // vm.deal(address(attacker), 5 ether);

    //     // vm.prank(address(attacker));
    //     // attacker.attack{value: 1 ether}();

    //     // // Assert
    //     // uint256 fundedAmount = fundMe.getAddressToAmountFunded(address(attacker));

    //     // // Should reflect actual contributions, not corrupted
    //     // assertGt(fundedAmount, 0);

    //     // // Ensure contract balance is consistent
    //     // assertEq(address(fundMe).balance, fundedAmount);
    //     // }

    //     // function testPriceFeedVersionIsAccurate() public view {
    //     //     if (block.chainid == 11155111) {
    //     //         uint256 version = fundMe.getVersion();
    //     //         assertEq(version, 4);
    //     //     } else if (block.chainid == 1) {
    //     //         uint256 version = fundMe.getVersion();
    //     //         assertEq(version, 6);
    //     //     }
    //     // }

    ///////////////////////////////////////////
    ///         FINALIZATION TESTS           ///
    ///////////////////////////////////////////
    function testFinalizeCampaignBeforeDeadlineReverts() public {
        vm.expectRevert(FundMe.FundMe__DeadlineNotYetPleaseWait.selector);
        fundMe.finalizeCampaign();
    }

    function testFinalizeCampaignAfterDeadlineAndGoalNotReachedSetsFailed() public userFunded {
        vm.warp(fundMe.i_deadline() + 1);

        fundMe.finalizeCampaign();

        assertEq(uint256(fundMe.getState()), uint256(FundMe.FundMeState.FAILED));
    }

    function testFinalizeCampaignAtDeadlineAndGoalNotReachedSetsFailed() public {
        vm.warp(fundMe.i_deadline());

        fundMe.finalizeCampaign();

        assertEq(uint256(fundMe.getState()), uint256(FundMe.FundMeState.FAILED));
    }

    function testCannotFinalizeCampaignTwice() public {
        vm.warp(fundMe.i_deadline());
        fundMe.finalizeCampaign();

        vm.expectRevert(FundMe.FundMe__CampaignAlreadyFinalized.selector);
        fundMe.finalizeCampaign();
    }

    function testCannotFinalizeSuccessfulCampaign() public {
        vm.prank(USER);
        fundMe.fund{value: GOAL_ETH}();

        vm.warp(fundMe.i_deadline());

        vm.expectRevert(FundMe.FundMe__CampaignAlreadyFinalized.selector);
        fundMe.finalizeCampaign();
    }

    ///////////////////////////////////////////
    ///          WITHDRAWAL TESTS            ///
    ///////////////////////////////////////////
    function testOnlyOwnerCanWithdrawFunds() public userFunded {
        vm.prank(USER);
        vm.expectRevert();
        fundMe.ownerWithdraw(GOAL_ETH);
    }

    function testWithdrawFailsIfCampaignNotSuccessful() public {
        vm.expectRevert(FundMe.FundMe__NotSuccessful.selector);
        fundMe.ownerWithdraw(0);
    }

    function testWithdrawRevertsIfAmountTooHigh() public fullGoalFunded {
        vm.expectRevert(FundMe.FundMe__InsufficientBalance.selector);
        fundMe.ownerWithdraw(address(fundMe).balance + 1);
    }

        function testOwnerWithdrawZeroAmountUsesFullBalance() public fullGoalFunded {
            vm.prank(fundMe.getOwner());
            fundMe.ownerWithdraw(0);

            assertEq(address(fundMe).balance, 0);
        }

        function testPartialWithdrawWorks() public fullGoalFunded {
            uint256 withdrawAmount = 2 ether;

            fundMe.ownerWithdraw(withdrawAmount);

            assertEq(address(fundMe).balance, 3 ether);
        }

        function testWithdrawDeductsCorrectPlatformFee() public fullGoalFunded{
        uint256 feeBefore = FEE_RECIPIENT.balance;

        fundMe.ownerWithdraw(0);

        uint256 actualFee = FEE_RECIPIENT.balance - feeBefore;
        uint256 expectedFee = (Math.mulDiv(GOAL_ETH, PLATFORM_FEE_BPS, BPS));

        assertEq(actualFee, expectedFee);
    }

    function testWithdrawPaysOwnerCorrectAmount() public fullGoalFunded{
        uint256 ownerBalanceBefore = address(this).balance;

        fundMe.ownerWithdraw(0);

        uint256 ownerBalanceAfter = address(this).balance;
        uint256 expectedPayout = GOAL_ETH - (Math.mulDiv(GOAL_ETH, PLATFORM_FEE_BPS, BPS));

        assertEq(ownerBalanceAfter - ownerBalanceBefore, expectedPayout);
    }

    function testWithdrawRevertsIfNotSuccessful() public userFunded {
            vm.expectRevert(FundMe.FundMe__NotSuccessful.selector);
            fundMe.ownerWithdraw(0);
        }

    //     function testWithdrawExactFeeAndPayout() public fullGoalFunded {
    //         // Arrange
    //         uint256 contractBalanceBefore = address(fundMe).balance;
    //         uint256 feeRecipientBalanceBefore = address(FEE_RECIPIENT).balance;

    //         // Act
    //         fundMe.ownerWithdraw(0);

    //         // Assert
    //         uint256 contractBalanceAfter = address(fundMe).balance;
    //         uint256 feeRecipientBalanceAfter = address(FEE_RECIPIENT).balance;

    //         // fee calculation
    //         uint256 expectedFee = (contractBalanceBefore * PLATFORM_FEE_BPS) / BPS;

    //         // fee received
    //         uint256 actualFee = feeRecipientBalanceAfter - feeRecipientBalanceBefore;

    //         // fee exact?
    //         assertEq(expectedFee, actualFee);

    //         // contract drained?
    //         assertEq(contractBalanceAfter, 0);

    //         // is fee + payout = total balance?
    //         uint256 payout = contractBalanceBefore - expectedFee;

    //         assertEq(payout + actualFee, contractBalanceBefore);
    //     }

    //     function testWithdrawFailsIfFeeTransferFails() public {
    //         RevertingReceiver badRecipient = new RevertingReceiver();

    //         mockPriceFeed = new MockV3Aggregator(DECIMALS, ETHPRICE);
    //         FundMe badFundMe =
    //             new FundMe(address(mockPriceFeed), GOAL, address(badRecipient), PLATFORM_FEE_BPS, REFUND_FEE_BPS, DURATION);

    //         vm.prank(USER);
    //         badFundMe.fund{value: GOAL}();

    //         vm.expectRevert(FundMe__WithdrawFailed.selector);
    //         badFundMe.ownerWithdraw(0);
    //     }

   ///////////////////////////////////////////
    ///             REFUND TESTS             ///
    ///////////////////////////////////////////
    //     function testCannotRefundIfGoalReached() public fullGoalFunded {
    //         vm.prank(USER);
    //         vm.expectRevert();
    //         fundMe.refund();
    //     }

    //     function testCannotRefundBeforeDeadline() public userFunded {
    //         vm.prank(USER);
    //         vm.expectRevert();
    //         fundMe.refund();
    //     }

    //     function testCannotRefundIfUserNeverFunded() public {
    //         vm.warp(block.timestamp + 30 days + 1); // move past deadline
    //         vm.prank(USER);
    //         vm.expectRevert();
    //         fundMe.refund();
    //     }

    //     function testRefundAtExactDeadline() public userFunded {
    //         vm.warp(fundMe.i_deadline()); // exact deadline

    //         vm.prank(USER);
    //         fundMe.refund(); // should PASS
    //     }

    //     function testRefundWorksAfterFailure() public userFunded {
    //         uint256 userBalanceBeforeRefund = address(USER).balance;

    //         vm.warp(block.timestamp + 30 days + 1);

    //         vm.prank(USER);
    //         fundMe.refund();

    //         uint256 userBalanceAfterRefund = address(USER).balance;
    //         uint256 afterBeingFunded = fundMe.getAddressToAmountFunded(USER);

    //         assertGt(userBalanceAfterRefund, userBalanceBeforeRefund);
    //         assertEq(afterBeingFunded, 0);
    //     }

    //     // fee logic
    //     function testRefundDeductsCorrectFee() public userFunded {
    //         uint256 amountFunded = fundMe.getAddressToAmountFunded(USER);

    //         uint256 feeRecipientBefore = address(FEE_RECIPIENT).balance;
    //         uint256 userBefore = address(USER).balance;

    //         vm.warp(block.timestamp + 30 days + 1);

    //         vm.prank(USER);
    //         fundMe.refund();

    //         uint256 feeRecipientAfter = address(FEE_RECIPIENT).balance;
    //         uint256 userAfter = address(USER).balance;

    //         // Calculate expected fee
    //         uint256 expectedFee = (amountFunded * REFUND_FEE_BPS) / 10_000;
    //         uint256 expectedRefund = amountFunded - expectedFee;

    //         // Actual values
    //         uint256 actualFee = feeRecipientAfter - feeRecipientBefore;
    //         uint256 actualRefund = userAfter - userBefore;

    //         //Exact fee check
    //         assertEq(actualFee, expectedFee);

    //         //Exact refund check
    //         assertEq(actualRefund, expectedRefund);
    //     }

    //     function testCannotRefundTwice() public userFunded {
    //         vm.warp(block.timestamp + 30 days + 1);

    //         vm.prank(USER);
    //         fundMe.refund();

    //         vm.prank(USER);
    //         vm.expectRevert();
    //         fundMe.refund();
    //     }

    //     function testRefundUpdatesContractBalanceCorrectly() public userFunded {
    //         uint256 contractBalanceBefore = address(fundMe).balance;
    //         uint256 amountFunded = fundMe.getAddressToAmountFunded(USER);
    //         uint256 feeRecipientBefore = address(FEE_RECIPIENT).balance;
    //         uint256 userBalanceBefore = address(USER).balance;

    //         (uint256 expectedFee, uint256 expectedRefund) = getExpectedRefund(amountFunded);

    //         vm.warp(block.timestamp + 30 days + 1);

    //         vm.prank(USER);
    //         fundMe.refund();

    //         uint256 contractBalanceAfter = address(fundMe).balance;
    //         uint256 feeRecipientAfter = address(FEE_RECIPIENT).balance;
    //         uint256 userBalanceAfter = address(USER).balance;

    //         uint256 actualFee = feeRecipientAfter - feeRecipientBefore;
    //         uint256 actualRefund = userBalanceAfter - userBalanceBefore;

    //         assertEq(actualFee, expectedFee);
    //         assertEq(actualRefund, expectedRefund);
    //         assertEq(contractBalanceBefore - contractBalanceAfter, amountFunded);
    //         assertEq(expectedFee + expectedRefund, amountFunded);
    //         assertEq(contractBalanceAfter, 0);
    //     }

    //     function testMultipleUsersRefundCorrectly() public {
    //         // both users fund
    //         vm.prank(USER);
    //         fundMe.fund{value: 1 ether}();

    //         vm.prank(USER2);
    //         fundMe.fund{value: 2 ether}();

    //         uint256 totalFunded = 3 ether;

    //         // Expected refunds
    //         (uint256 fee1, uint256 refund1) = getExpectedRefund(1 ether);
    //         (uint256 fee2, uint256 refund2) = getExpectedRefund(2 ether);

    //         uint256 feeRecipientBefore = address(FEE_RECIPIENT).balance;

    //         vm.warp(block.timestamp + 30 days + 1); // time has passed & GOAL not reached

    //         // Both users refund
    //         vm.prank(USER);
    //         fundMe.refund();

    //         vm.prank(USER2);
    //         fundMe.refund();

    //         // Assrt
    //         uint256 contractBalanceAfter = address(fundMe).balance;
    //         uint256 feeRecipientAfter = address(FEE_RECIPIENT).balance;

    //         uint256 totalFees = feeRecipientAfter - feeRecipientBefore;

    //         // did all funds leave the contract?
    //         assertEq(contractBalanceAfter, 0);

    //         //total fees collected
    //         assertEq(totalFees, fee1 + fee2);

    //         assertEq(totalFunded, refund1 + refund2 + fee1 + fee2);

    //         assertEq(fundMe.getAddressToAmountFunded(USER), 0);
    //         assertEq(fundMe.getAddressToAmountFunded(USER2), 0);
    //     }

    //     function testRefundFailsIfFeeTransferFails() public {
    //         RevertingReceiver badRecipient = new RevertingReceiver();

    //         // Deploy new FundMe with malicious fee recipient
    //         mockPriceFeed = new MockV3Aggregator(DECIMALS, ETHPRICE);
    //         FundMe badFundMe =
    //             new FundMe(address(mockPriceFeed), GOAL, address(badRecipient), PLATFORM_FEE_BPS, REFUND_FEE_BPS, DURATION);

    //         vm.deal(USER, 10 ether);

    //         vm.prank(USER);
    //         badFundMe.fund{value: 1 ether}();

    //         vm.warp(block.timestamp + 30 days + 1);

    //         vm.prank(USER);
    //         vm.expectRevert(FundMe__RefundFailed.selector);
    //         badFundMe.refund();
    //     }

    //     /*//////////////////////////////////////////////////////////////
    //                                 HELPERS
    //     //////////////////////////////////////////////////////////////*/
    //     function getExpectedRefund(uint256 amount) internal pure returns (uint256 fee, uint256 refund) {
    //         fee = (amount * REFUND_FEE_BPS) / 10_000;
    //         refund = amount - fee;
    //     }

    //     function testViewFunctionsReturnCorrectState() public userFunded {
    //         assertEq(fundMe.getTotalAmountFunded(), SEND_VALUE);
    //         assertEq(fundMe.getAddressToAmountFunded(USER), SEND_VALUE);
    //         assertGt(fundMe.getDeadline(), block.timestamp);
    //     }

    // /**
    //  * @author  . Barney
    //  * @title   . Reverting Receiver Contract for testing refund reversion scenarios
    //  * @dev     . This contract is designed to simulate a malicious or faulty recipient that reverts on receiving ETH, allowing us to test the refund logic in the FundMe contract under conditions where the fee transfer fails. By using this contract as the fee recipient, we can ensure that our refund function correctly handles reversion scenarios and does not allow users to receive refunds without paying the required fee.
    //  * @notice  . This contract should be used in conjunction with the FundMe contract's refund function to test the behavior when the fee transfer fails. When the FundMe contract attempts to transfer the fee to this RevertingReceiver, it will revert, allowing us to verify that the refund function properly reverts the entire transaction and does not allow the user to receive a refund without paying the fee.
    //  */
    // contract RevertingReceiver {
    //     //Malicious Contract
    //     error RevertingReceiver__RevertOnReceive();

    //     receive() external payable {
    //         revert RevertingReceiver__RevertOnReceive();
    //     }
}
