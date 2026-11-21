//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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

    uint256 constant GOAL_USD = 10_000e18;
    uint256 constant MINIMUM_USD = 5e18;

    uint256 constant GOAL_ETH = 5 ether;
    uint256 constant MINIMUM_ETH = 0.0025 ether;

    uint256 constant DURATION = 60;
    uint256 constant BPS = 10_000;
    uint256 constant PLATFORM_FEE_BPS = 200;
    uint256 constant REFUND_FEE_BPS = 100;
    uint8 constant DECIMALS = 8;
    int256 constant ETHPRICE = 2000e8; // $2000

    function setUp() external {
        mockPriceFeed = new MockV3Aggregator(DECIMALS, ETHPRICE); // 2000 USD with 8 decimals
        fundMe = new FundMe(
            address(mockPriceFeed), MINIMUM_USD, GOAL_USD, FEE_RECIPIENT, PLATFORM_FEE_BPS, REFUND_FEE_BPS, DURATION
        );
        vm.deal(USER, STARTING_BALANCE);
        vm.deal(USER2, STARTING_BALANCE);
        vm.deal(USER3, STARTING_BALANCE);
    }

    // checks that a valid contribution is recorded against the correct address.
    function testFuzz_FundWorks(uint256 amount) public {
        //0.0025 ether is 5 dollars with 18 dec
        amount = bound(amount, 0.0025 ether, 10 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        assertEq(fundMe.getAddressToAmountFunded(USER), amount);
    }

    function testFuzz_FundRevertsIfTooSmall(uint256 amount) public {
        amount = bound(amount, 1 wei, 0.0024 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        vm.expectRevert(FundMe.FundMe__SpendMoreEth.selector);
        fundMe.fund{value: amount}();
    }

    function testFuzz_FundAccumulates(uint256 amountA, uint256 amountB) public {
        uint256 MIN_ETH = 0.0025 ether; //$5

        amountA = bound(amountA, MIN_ETH, 2 ether);
        amountB = bound(amountB, MIN_ETH, 2 ether);

        vm.deal(USER, amountA + amountB);

        vm.startPrank(USER);

        fundMe.fund{value: amountA}();
        fundMe.fund{value: amountB}();

        vm.stopPrank();

        assertEq(fundMe.getAddressToAmountFunded(USER), amountA + amountB);
    }

    function testFuzz_MultipleUsersFunding(uint256 amountA, uint256 amountB) public {
        uint256 MIN_ETH = 0.0025 ether;

        amountA = bound(amountA, MIN_ETH, 2 ether);
        amountB = bound(amountB, MIN_ETH, 2 ether);

        vm.deal(USER, amountA);
        vm.deal(USER2, amountB);

        vm.prank(USER);
        fundMe.fund{value: amountA}();

        vm.prank(USER2);
        fundMe.fund{value: amountB}();

        assertEq(fundMe.getAddressToAmountFunded(USER), amountA);
        assertEq(fundMe.getAddressToAmountFunded(USER2), amountB);
    }

    function testFuzz_FundAcceptsExactMinimum(uint256 amount) public {
        amount = bound(amount, MINIMUM_ETH, MINIMUM_ETH);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        assertEq(fundMe.getAddressToAmountFunded(USER), MINIMUM_ETH);
    }

    function testFuzz_FundRevertsAfterDeadline(uint256 amount) public {
        amount = bound(amount, MINIMUM_ETH, 1 ether);

        vm.warp(fundMe.getDeadline());

        vm.deal(USER, amount);

        vm.expectRevert(FundMe.FundMe__CampaignEnded.selector);
        vm.prank(USER);
        fundMe.fund{value: amount}();
    }

    function testFuzz_FundRevertsAfterGoalReached(uint256 amount) public {
        amount = bound(amount, GOAL_ETH, 10 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        assertEq(uint256(fundMe.getState()), uint256(FundMe.FundMeState.SUCCESS));

        vm.deal(USER2, MINIMUM_ETH);

        vm.expectRevert(FundMe.FundMe__NotActive.selector);
        vm.prank(USER2);
        fundMe.fund{value: MINIMUM_ETH}();
    }

    /*//////////////////////////////////////////////////////////////
                              REFUND FUZZ
    //////////////////////////////////////////////////////////////*/
    function testFuzz_RefundWorks(uint256 amount) public {
        amount = bound(amount, MINIMUM_ETH, 2 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        vm.warp(fundMe.getDeadline());

        uint256 userBalanceBefore = USER.balance;
        uint256 feeRecipientBefore = FEE_RECIPIENT.balance;

        uint256 fee = (amount * REFUND_FEE_BPS) / BPS;
        uint256 refundAmount = amount - fee;

        vm.prank(USER);
        fundMe.refund();

        assertEq(USER.balance, userBalanceBefore + refundAmount);
        assertEq(FEE_RECIPIENT.balance, feeRecipientBefore + fee);
        assertEq(fundMe.getAddressToAmountFunded(USER), 0);
        assertEq(fundMe.getPlatformFeesCollected(), fee);
        assertEq(address(fundMe).balance, 0);
    }

    function test_RefundRevertsIfNoFunds() public {
        vm.warp(fundMe.getDeadline());

        vm.expectRevert(FundMe.FundMe__NoFundsToWithdraw.selector);
        vm.prank(USER);
        fundMe.refund();
    }

    function testFuzz_RefundRevertsBeforeDeadline(uint256 amount) public {
        amount = bound(amount, MINIMUM_ETH, 2 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        vm.expectRevert(FundMe.FundMe__DeadlineNotYetPleaseWait.selector);
        vm.prank(USER);
        fundMe.refund();
    }

    function testFuzz_RefundOnlyOnce(uint256 amount) public {
        amount = bound(amount, MINIMUM_ETH, 2 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        vm.warp(fundMe.getDeadline());

        vm.prank(USER);
        fundMe.refund();

        vm.expectRevert(FundMe.FundMe__NoFundsToWithdraw.selector);
        vm.prank(USER);
        fundMe.refund(); // second attemp to refund
    }

    function testFuzz_RefundRevertsIfCampaignSuccessful(uint256 amount) public {
        amount = bound(amount, GOAL_ETH, 10 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        assertEq(uint256(fundMe.getState()), uint256(FundMe.FundMeState.SUCCESS));

        vm.warp(fundMe.getDeadline());

        vm.expectRevert(FundMe.FundMe__GoalReached.selector);
        vm.prank(USER);
        fundMe.refund();
    }

    // A user who contributes multiple times must receive a refund based on their total recorded contribution.
    function testFuzz_RefundMultipleContributions(uint256 amountA, uint256 amountB) public {
        amountA = bound(amountA, MINIMUM_ETH, 2 ether);
        amountB = bound(amountB, MINIMUM_ETH, 2 ether);

        uint256 totalAmount = amountA + amountB;

        vm.deal(USER, totalAmount);

        vm.startPrank(USER);

        fundMe.fund{value: amountA}();
        fundMe.fund{value: amountB}();

        vm.stopPrank();

        vm.warp(fundMe.getDeadline());

        uint256 fee = Math.mulDiv(totalAmount, REFUND_FEE_BPS, BPS);
        uint256 expectedRefund = totalAmount - fee;

        uint256 userBalanceBefore = USER.balance;

        vm.prank(USER);
        fundMe.refund();

        assertEq(USER.balance, userBalanceBefore + expectedRefund);
        assertEq(fundMe.getAddressToAmountFunded(USER), 0);
        assertEq(fundMe.getPlatformFeesCollected(), fee);
    }

    function testFuzz_RefundDoesNotAffectOtherFunders(uint256 amountA, uint256 amountB) public {
        amountA = bound(amountA, MINIMUM_ETH, 2 ether);
        amountB = bound(amountB, MINIMUM_ETH, 2 ether);

        vm.deal(USER, amountA);
        vm.deal(USER2, amountB);

        vm.prank(USER);
        fundMe.fund{value: amountA}();

        vm.prank(USER2);
        fundMe.fund{value: amountB}();

        vm.warp(fundMe.getDeadline());

        vm.prank(USER);
        fundMe.refund();

        assertEq(fundMe.getAddressToAmountFunded(USER), 0);
        assertEq(fundMe.getAddressToAmountFunded(USER2), amountB);
    }

    /*//////////////////////////////////////////////////////////////
                                  WITHDRAW FUZZ
        //////////////////////////////////////////////////////////////*/
    function testFuzz_WithdrawWorks(uint256 amount) public {
        amount = bound(amount, GOAL_ETH, 10 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        address owner = fundMe.getOwner();

        uint256 ownerBalanceBeforeWithdraw = owner.balance;
        uint256 totalWithdrawnBefore = fundMe.getTotalWithdrawnByOwner();
        uint256 feeRecipientBefore = FEE_RECIPIENT.balance;

        vm.prank(owner);
        fundMe.ownerWithdraw(0); // assuming full withdraw

        uint256 fee = (amount * PLATFORM_FEE_BPS) / BPS;
        uint256 payout = amount - fee;

        uint256 contractBal = address(fundMe).balance;
        uint256 totalWithdrawnByOwner = fundMe.getTotalWithdrawnByOwner();
        uint256 feeCollected = fundMe.getPlatformFeesCollected();

        assertEq(owner.balance, ownerBalanceBeforeWithdraw + payout);
        assertEq(totalWithdrawnByOwner, totalWithdrawnBefore + payout);
        assertEq(FEE_RECIPIENT.balance, feeRecipientBefore + fee);
        assertEq(feeCollected, fee);
        assertEq(contractBal, 0);
    }

    function testFuzz_WithdrawOnlyOwner(uint256 amount) public {
        amount = bound(amount, GOAL_ETH, 10 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        vm.prank(USER); // NOT owner
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", USER));
        fundMe.ownerWithdraw(0);
    }

    function testFuzz_WithdrawFailsIfNotSuccessful(uint256 amount) public {
        amount = bound(amount, 0.0025 ether, GOAL_ETH - 1);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        address owner = fundMe.getOwner();

        vm.prank(owner);
        vm.expectRevert(FundMe.FundMe__NotSuccessful.selector);
        fundMe.ownerWithdraw(0);
    }

    function testFuzz_WithdrawOnlyOnce(uint256 amount) public {
        amount = bound(amount, GOAL_ETH, 10 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        address owner = fundMe.getOwner();

        vm.startPrank(owner);

        fundMe.ownerWithdraw(0);

        vm.expectRevert(FundMe.FundMe__NoFundsToWithdraw.selector); // second withdraw should fail
        fundMe.ownerWithdraw(0);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           WITHDRAW EDGE FUZZ
    //////////////////////////////////////////////////////////////*/
    function testFuzz_PartialWithdrawWorks(uint256 contribution, uint256 withdrawAmount) public {
        contribution = bound(contribution, GOAL_ETH, 10 ether);
        withdrawAmount = bound(withdrawAmount, 1, contribution - 1); // guarantees that funds remain in the contract.

        vm.deal(USER, contribution);

        vm.prank(USER);
        fundMe.fund{value: contribution}();

        address owner = fundMe.getOwner();

        uint256 ownerBalanceBefore = owner.balance;
        uint256 feeRecipientBefore = FEE_RECIPIENT.balance;

        uint256 fee = (withdrawAmount * PLATFORM_FEE_BPS) / BPS;
        uint256 payout = withdrawAmount - fee;

        vm.prank(owner);
        fundMe.ownerWithdraw(withdrawAmount);

        assertEq(owner.balance, ownerBalanceBefore + payout);
        assertEq(FEE_RECIPIENT.balance, feeRecipientBefore + fee);

        assertEq(address(fundMe).balance, contribution - withdrawAmount);
        assertEq(fundMe.getTotalWithdrawnByOwner(), payout);
        assertEq(fundMe.getPlatformFeesCollected(), fee);
    }

    function testFuzz_WithdrawExceedingBalanceReverts(uint256 amount) public {
        amount = bound(amount, GOAL_ETH, 10 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        address owner = fundMe.getOwner();

        vm.expectRevert(FundMe.FundMe__InsufficientBalance.selector);
        vm.prank(owner);
        fundMe.ownerWithdraw(amount + 1);
    }

    function testFuzz_MultiplePartialWithdrawals(
        uint256 contribution,
        uint256 firstWithdrawal,
        uint256 secondWithdrawal
    ) public {
        contribution = bound(contribution, GOAL_ETH, 10 ether);

        firstWithdrawal = bound(firstWithdrawal, 1, contribution - 1);

        uint256 remainingAfterFirst = contribution - firstWithdrawal;

        secondWithdrawal = bound(secondWithdrawal, 1, remainingAfterFirst);

        vm.deal(USER, contribution);

        vm.prank(USER);
        fundMe.fund{value: contribution}();

        address owner = fundMe.getOwner();

        uint256 ownerBalanceBefore = owner.balance;
        uint256 feeRecipientBefore = FEE_RECIPIENT.balance;

        uint256 firstFee = (firstWithdrawal * PLATFORM_FEE_BPS) / BPS;
        uint256 secondFee = (secondWithdrawal * PLATFORM_FEE_BPS) / BPS;

        vm.startPrank(owner);

        fundMe.ownerWithdraw(firstWithdrawal);
        fundMe.ownerWithdraw(secondWithdrawal);

        vm.stopPrank();

        uint256 totalFees = firstFee + secondFee;
        uint256 totalPayout = (firstWithdrawal - firstFee) + (secondWithdrawal - secondFee);

        assertEq(owner.balance, ownerBalanceBefore + totalPayout);
        assertEq(FEE_RECIPIENT.balance, feeRecipientBefore + totalFees);

        assertEq(address(fundMe).balance, contribution - firstWithdrawal - secondWithdrawal);

        assertEq(fundMe.getTotalWithdrawnByOwner(), totalPayout);
        assertEq(fundMe.getPlatformFeesCollected(), totalFees);
    }
}
