//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract FundMeTest is Test {
    error FundMe__InsufficientBalance();
    error FundMe__NotSuccessful();
    error FundMe__RefundFailed();
    error FundMe__WithdrawFailed();

    FundMe public fundMe;
    MockV3Aggregator mockPriceFeed;

    receive() external payable {} // to make the test contract receive ETH

    address USER = makeAddr("user");
    address USER2 = makeAddr("user2");
    address USER3 = makeAddr("user3");
    address FEE_RECIPIENT = makeAddr("feeRecipient");

    uint256 constant SEND_VALUE = 0.1 ether; //100000000000000000
    uint256 constant STARTING_BALANCE = 10 ether;
    uint256 constant GOAL = 5 ether;
    uint256 constant BPS = 10_000;
    uint256 constant PLATFORM_FEE_BPS = 200;
    uint256 constant REFUND_FEE_BPS = 100;
    uint8 constant DECIMALS = 8;
    int256 constant ETHPRICE = 2000e8; // $2000

    function setUp() external {
        mockPriceFeed = new MockV3Aggregator(DECIMALS, ETHPRICE); // 2000 USD with 8 decimals
        fundMe = new FundMe(address(mockPriceFeed), GOAL, FEE_RECIPIENT, PLATFORM_FEE_BPS, REFUND_FEE_BPS);
        vm.deal(USER, STARTING_BALANCE);
        vm.deal(USER2, STARTING_BALANCE);
        vm.deal(USER3, STARTING_BALANCE);
    }

    modifier userFunded() {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();
        _;
    }

    modifier fullGoalFunded() {
        vm.prank(USER);
        fundMe.fund{value: GOAL}();
        _;
    }

    // constructor function tests/General
    function testInitialStateIsActive() public {
        assertEq(uint256(fundMe.getState()), 0); // ACTIVE
    }

    function testMinimumDollarIsFive() public {
        assertEq(fundMe.MINIMUM_USD(), uint256(5e18));
    }

    function testOwnerIsMsgSender() public view {
        assertEq(fundMe.getOwner(), address(this));
    }

    function testGoalIsSetCorrectly() public view {
        assertEq(fundMe.i_goal(), GOAL);
    }

    function testFeeRecipientIsSet() public view {
        assertEq(fundMe.i_feeRecipient(), FEE_RECIPIENT);
    }

    function testReceiveFunctionTriggersFund() public {
        vm.prank(USER3);
        (bool success,) = address(fundMe).call{value: 1 ether}(""); //USER3 didn't call fund() directly, but sent ETH to the contract address, which should trigger the receive function and fund the contract

        assertTrue(success);
        assertEq(fundMe.getAddressToAmountFunded(USER3), 1 ether);
    }

    function testFallbackFunctionTriggersFund() public {
        vm.prank(USER3);
        (bool success,) = address(fundMe).call{value: 2 ether}("0x1234"); // sending data that doesn't match any function signature should trigger the fallback function, which should also fund the contract

        assertTrue(success);
        assertEq(fundMe.getAddressToAmountFunded(USER3), 2 ether);
    }

    function testViewFunctionsReturnCorrectState() public userFunded {
        assertEq(fundMe.getTotalAmountFunded(), SEND_VALUE);
        assertEq(fundMe.getAddressToAmountFunded(USER), SEND_VALUE);
        assertGt(fundMe.getDeadline(), block.timestamp);
    }

    // function testFallbackReentrancyDoesNotBreakAccounting() public {
    // MaliciousFunder attacker = new MaliciousFunder(address(fundMe));

    // vm.deal(address(attacker), 5 ether);

    // vm.prank(address(attacker));
    // attacker.attack{value: 1 ether}();

    // // Assert
    // uint256 fundedAmount = fundMe.getAddressToAmountFunded(address(attacker));

    // // Should reflect actual contributions, not corrupted
    // assertGt(fundedAmount, 0);

    // // Ensure contract balance is consistent
    // assertEq(address(fundMe).balance, fundedAmount);
    // }

    // function testPriceFeedVersionIsAccurate() public view {
    //     if (block.chainid == 11155111) {
    //         uint256 version = fundMe.getVersion();
    //         assertEq(version, 4);
    //     } else if (block.chainid == 1) {
    //         uint256 version = fundMe.getVersion();
    //         assertEq(version, 6);
    //     }
    // }

    // Funding Tests
    function testPriceFeedVersion() public {
        uint256 version = fundMe.getVersion();
        assertEq(version, 0);
    }

    function testFundFailsWithoutEnoughETH() public {
        vm.expectRevert();
        fundMe.fund(); //send 0 value
    }

    function testFundRevertsIfBelowMinimum() public {
        vm.prank(USER);

        vm.expectRevert(); // MINIMUM_USD check
        fundMe.fund{value: 1}(); // too small
    }

    function testFundUpdatesFundedMapping() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        uint256 amountFunded = fundMe.getAddressToAmountFunded(USER);
        assertEq(amountFunded, SEND_VALUE);
    }

    function testAddsFunderToArrayOfFunders() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        address funder = fundMe.getFunder(0);
        assertEq(funder, USER);
    }

    function testMultipleFunders() public {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        vm.prank(USER2);
        fundMe.fund{value: SEND_VALUE}();

        assertEq(fundMe.getFunder(0), USER);
        assertEq(fundMe.getFunder(1), USER2);
    }

    function testGoalReachedChangesState() public {
        vm.prank(USER);
        fundMe.fund{value: GOAL}();

        // assuming contract auto-checks goal
        assertEq(uint256(fundMe.getState()), 1); // SUCCESS
    }

    // Withdraw Tests
    function testOnlyOwnerCanWithdrawFunds() public userFunded {
        vm.prank(USER);
        vm.expectRevert();
        fundMe.ownerWithdraw(GOAL);
    }

    function testOwnerWithdrawZeroAmountUsesFullBalance() public fullGoalFunded {
        vm.prank(fundMe.getOwner());
        fundMe.ownerWithdraw(0);

        assertEq(address(fundMe).balance, 0);
    }

    function testWithdrawWorks() public {
        // Arrange
        vm.prank(USER);
        fundMe.fund{value: GOAL}(); // this will trigger GOAL success
        // state should be SUCCESS

        uint256 contractBalanceBefore = address(fundMe).balance;

        // Act
        fundMe.ownerWithdraw(0); // full balance withdraw

        uint256 contractBalanceAfter = address(fundMe).balance;
        //Contract drained
        assertEq(contractBalanceAfter, 0);
    }

    function testPartialWithdrawWorks() public fullGoalFunded {
        uint256 withdrawAmount = 2 ether;

        fundMe.ownerWithdraw(withdrawAmount);

        assertGt(address(fundMe).balance, 0);
    }

    function testWithdrawWorksWithFullSystemLogic() public fullGoalFunded {
        // Arrage
        uint256 contractBalanceBefore = address(fundMe).balance;
        uint256 ownerBalanceBefore = address(this).balance;
        uint256 feeRecipientBalanceBefore = address(FEE_RECIPIENT).balance;

        // Act
        fundMe.ownerWithdraw(0); //full withdraw

        // Assert
        uint256 contractBalanceAfter = address(fundMe).balance;
        uint256 ownerBalanceAfter = address(this).balance;
        uint256 feeRecipientBalanceAfter = address(FEE_RECIPIENT).balance;

        // contract got draained?
        assertEq(contractBalanceAfter, 0);

        // fee recipient got paid?
        assertGt(feeRecipientBalanceAfter, feeRecipientBalanceBefore);

        // owner got paid?
        assertGt(ownerBalanceAfter, ownerBalanceBefore);
    }

    function testWithdrawExactFeeAndPayout() public fullGoalFunded {
        // Arrange
        uint256 contractBalanceBefore = address(fundMe).balance;
        uint256 feeRecipientBalanceBefore = address(FEE_RECIPIENT).balance;

        // Act
        fundMe.ownerWithdraw(0);

        // Assert
        uint256 contractBalanceAfter = address(fundMe).balance;
        uint256 feeRecipientBalanceAfter = address(FEE_RECIPIENT).balance;

        // fee calculation
        uint256 expectedFee = (contractBalanceBefore * PLATFORM_FEE_BPS) / BPS;

        // fee received
        uint256 actualFee = feeRecipientBalanceAfter - feeRecipientBalanceBefore;

        // fee exact?
        assertEq(expectedFee, actualFee);

        // contract drained?
        assertEq(contractBalanceAfter, 0);

        // is fee + payout = total balance?
        uint256 payout = contractBalanceBefore - expectedFee;

        assertEq(payout + actualFee, contractBalanceBefore);
    }

    function testWithdrawRevertsIfAmountTooHigh() public fullGoalFunded {
        uint256 tooMuch = address(fundMe).balance + 1;

        vm.expectRevert(FundMe__InsufficientBalance.selector);
        fundMe.ownerWithdraw(tooMuch);
    }

    function testWithdrawRevertsIfNotSuccessful() public userFunded {
        vm.expectRevert(FundMe__NotSuccessful.selector);
        fundMe.ownerWithdraw(0);
    }

    function testWithdrawFailsIfFeeTransferFails() public {
        RevertingReceiver badRecipient = new RevertingReceiver();

        mockPriceFeed = new MockV3Aggregator(DECIMALS, ETHPRICE);
        FundMe badFundMe =
            new FundMe(address(mockPriceFeed), GOAL, address(badRecipient), PLATFORM_FEE_BPS, REFUND_FEE_BPS);

        vm.prank(USER);
        badFundMe.fund{value: GOAL}();

        vm.expectRevert(FundMe__WithdrawFailed.selector);
        badFundMe.ownerWithdraw(0);
    }

    // Refund Tests
    function testCannotRefundIfGoalReached() public fullGoalFunded {
        vm.prank(USER);
        vm.expectRevert();
        fundMe.refund();
    }

    function testCannotRefundBeforeDeadline() public userFunded {
        vm.prank(USER);
        vm.expectRevert();
        fundMe.refund();
    }

    function testCannotRefundIfUserNeverFunded() public {
        vm.warp(block.timestamp + 30 days + 1); // move past deadline
        vm.prank(USER);
        vm.expectRevert();
        fundMe.refund();
    }

    function testRefundAtExactDeadline() public userFunded {
        vm.warp(fundMe.i_deadline()); // exact deadline

        vm.prank(USER);
        fundMe.refund(); // should PASS
    }

    function testRefundWorksAfterFailure() public userFunded {
        uint256 userBalanceBeforeRefund = address(USER).balance;
        uint256 amountFunded = fundMe.getAddressToAmountFunded(USER);

        vm.warp(block.timestamp + 30 days + 1);

        vm.prank(USER);
        fundMe.refund();

        uint256 userBalanceAfterRefund = address(USER).balance;
        uint256 afterBeingFunded = fundMe.getAddressToAmountFunded(USER);

        assertGt(userBalanceAfterRefund, userBalanceBeforeRefund);
        assertEq(afterBeingFunded, 0);
    }

    // fee logic
    function testRefundDeductsCorrectFee() public userFunded {
        uint256 amountFunded = fundMe.getAddressToAmountFunded(USER);

        uint256 feeRecipientBefore = address(FEE_RECIPIENT).balance;
        uint256 userBefore = address(USER).balance;

        vm.warp(block.timestamp + 30 days + 1);

        vm.prank(USER);
        fundMe.refund();

        uint256 feeRecipientAfter = address(FEE_RECIPIENT).balance;
        uint256 userAfter = address(USER).balance;

        // Calculate expected fee
        uint256 expectedFee = (amountFunded * REFUND_FEE_BPS) / 10_000;
        uint256 expectedRefund = amountFunded - expectedFee;

        // Actual values
        uint256 actualFee = feeRecipientAfter - feeRecipientBefore;
        uint256 actualRefund = userAfter - userBefore;

        //Exact fee check
        assertEq(actualFee, expectedFee);

        //Exact refund check
        assertEq(actualRefund, expectedRefund);
    }

    function testCannotRefundTwice() public userFunded {
        vm.warp(block.timestamp + 30 days + 1);

        vm.prank(USER);
        fundMe.refund();

        vm.prank(USER);
        vm.expectRevert();
        fundMe.refund();
    }

    function testRefundUpdatesContractBalanceCorrectly() public userFunded {
        uint256 contractBalanceBefore = address(fundMe).balance;
        uint256 amountFunded = fundMe.getAddressToAmountFunded(USER);
        uint256 feeRecipientBefore = address(FEE_RECIPIENT).balance;
        uint256 userBalanceBefore = address(USER).balance;

        (uint256 expectedFee, uint256 expectedRefund) = getExpectedRefund(amountFunded);

        vm.warp(block.timestamp + 30 days + 1);

        vm.prank(USER);
        fundMe.refund();

        uint256 contractBalanceAfter = address(fundMe).balance;
        uint256 feeRecipientAfter = address(FEE_RECIPIENT).balance;
        uint256 userBalanceAfter = address(USER).balance;

        uint256 actualFee = feeRecipientAfter - feeRecipientBefore;
        uint256 actualRefund = userBalanceAfter - userBalanceBefore;

        assertEq(actualFee, expectedFee);
        assertEq(actualRefund, expectedRefund);
        assertEq(contractBalanceBefore - contractBalanceAfter, amountFunded);
        assertEq(expectedFee + expectedRefund, amountFunded);
        assertEq(contractBalanceAfter, 0);
    }

    function testMultipleUsersRefundCorrectly() public {
        // both users fund
        vm.prank(USER);
        fundMe.fund{value: 1 ether}();

        vm.prank(USER2);
        fundMe.fund{value: 2 ether}();

        uint256 totalFunded = 3 ether;

        // Expected refunds
        (uint256 fee1, uint256 refund1) = getExpectedRefund(1 ether);
        (uint256 fee2, uint256 refund2) = getExpectedRefund(2 ether);

        uint256 feeRecipientBefore = address(FEE_RECIPIENT).balance;

        vm.warp(block.timestamp + 30 days + 1); // time has passed & GOAL not reached

        // Both users refund
        vm.prank(USER);
        fundMe.refund();

        vm.prank(USER2);
        fundMe.refund();

        // Assrt
        uint256 contractBalanceAfter = address(fundMe).balance;
        uint256 feeRecipientAfter = address(FEE_RECIPIENT).balance;

        uint256 totalFees = feeRecipientAfter - feeRecipientBefore;

        // did all funds leave the contract?
        assertEq(contractBalanceAfter, 0);

        //total fees collected
        assertEq(totalFees, fee1 + fee2);

        assertEq(totalFunded, refund1 + refund2 + fee1 + fee2);

        assertEq(fundMe.getAddressToAmountFunded(USER), 0);
        assertEq(fundMe.getAddressToAmountFunded(USER2), 0);
    }

    function testRefundFailsIfFeeTransferFails() public {
        RevertingReceiver badRecipient = new RevertingReceiver();

        // Deploy new FundMe with malicious fee recipient
        mockPriceFeed = new MockV3Aggregator(DECIMALS, ETHPRICE);
        FundMe badFundMe =
            new FundMe(address(mockPriceFeed), GOAL, address(badRecipient), PLATFORM_FEE_BPS, REFUND_FEE_BPS);

        vm.deal(USER, 10 ether);

        vm.prank(USER);
        badFundMe.fund{value: 1 ether}();

        vm.warp(block.timestamp + 30 days + 1);

        vm.prank(USER);
        vm.expectRevert(FundMe__RefundFailed.selector);
        badFundMe.refund();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    function getExpectedRefund(uint256 amount) internal view returns (uint256 fee, uint256 refund) {
        fee = (amount * REFUND_FEE_BPS) / 10_000;
        refund = amount - fee;
    }
}

/**
 * @author  . Barney
 * @title   . Reverting Receiver Contract for testing refund reversion scenarios
 * @dev     . This contract is designed to simulate a malicious or faulty recipient that reverts on receiving ETH, allowing us to test the refund logic in the FundMe contract under conditions where the fee transfer fails. By using this contract as the fee recipient, we can ensure that our refund function correctly handles reversion scenarios and does not allow users to receive refunds without paying the required fee.
 * @notice  . This contract should be used in conjunction with the FundMe contract's refund function to test the behavior when the fee transfer fails. When the FundMe contract attempts to transfer the fee to this RevertingReceiver, it will revert, allowing us to verify that the refund function properly reverts the entire transaction and does not allow the user to receive a refund without paying the fee.
 */

contract RevertingReceiver {
    //Malicious Contract
    error RevertingReceiver__RevertOnReceive();

    receive() external payable {
        revert RevertingReceiver__RevertOnReceive();
    }
}

