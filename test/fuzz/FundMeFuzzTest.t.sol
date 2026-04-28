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
        vm.expectRevert();
        fundMe.fund{value: amount}();
    }

    function testFuzz_FundAccumulates(uint256 amountA, uint256 amountB) public {
        uint256 MIN_ETH = 0.0025 ether;

        amountA = bound(amountA, MIN_ETH, 2 ether);
        amountB = bound(amountB, MIN_ETH, 2 ether);

        vm.assume(amountA + amountB < GOAL);

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

    /*//////////////////////////////////////////////////////////////
                              REFUND FUZZ
    //////////////////////////////////////////////////////////////*/
    function testFuzz_RefundWorks(uint256 amount) public {
        uint256 MIN_ETH = 0.0025 ether;

        amount = bound(amount, MIN_ETH, 2 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        // move time forward (deadline passed)
        vm.warp(block.timestamp + 2 days);

        uint256 userBalanceBefore = USER.balance;
        uint256 feeRecipientBefore = FEE_RECIPIENT.balance;

        vm.prank(USER);
        fundMe.refund();

        uint256 fee = (amount * REFUND_FEE_BPS) / BPS;
        uint256 refundAmount = amount - fee;

        assertEq(USER.balance, userBalanceBefore + refundAmount);
        assertEq(FEE_RECIPIENT.balance, feeRecipientBefore + fee);
    }

    function testFuzz_RefundRevertsIfNoFunds(uint256 amount) public {
        amount = bound(amount, 0.0025 ether, 2 ether);

        vm.warp(block.timestamp + 2 days);

        vm.prank(USER);
        vm.expectRevert();
        fundMe.refund();
    }

    function testFuzz_RefundRevertsBeforeDeadline(uint256 amount) public {
        uint256 MIN_ETH = 0.0025 ether;

        amount = bound(amount, MIN_ETH, 2 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        // NO warp → still active

        vm.prank(USER);
        vm.expectRevert(); // Deadline not passed
        fundMe.refund();
    }

    function testFuzz_RefundOnlyOnce(uint256 amount) public {
        uint256 MIN_ETH = 0.0025 ether;

        amount = bound(amount, MIN_ETH, 2 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        vm.warp(block.timestamp + 2 days);

        vm.startPrank(USER);

        fundMe.refund();

        vm.expectRevert(); // second refund should fail
        fundMe.refund();

        vm.stopPrank();
    }

    function testFuzz_WithdrawWorks(uint256 amount) public {
        amount = bound(amount, GOAL, 10 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        address owner = fundMe.getOwner();

        uint256 ownerBalanceBefore = owner.balance;
        uint256 feeRecipientBefore = FEE_RECIPIENT.balance;

        vm.prank(owner);
        fundMe.ownerWithdraw(0); // assuming full withdraw

        uint256 fee = (amount * PLATFORM_FEE_BPS) / BPS;
        uint256 payout = amount - fee;

        assertEq(owner.balance, ownerBalanceBefore + payout);
        assertEq(FEE_RECIPIENT.balance, feeRecipientBefore + fee);
    }

    function testFuzz_WithdrawOnlyOwner(uint256 amount) public {
        amount = bound(amount, GOAL, 10 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        vm.prank(USER); // NOT owner
        vm.expectRevert();
        fundMe.ownerWithdraw(0);
    }

    function testFuzz_WithdrawFailsIfNotSuccessful(uint256 amount) public {
        amount = bound(amount, 0.0025 ether, GOAL - 1);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        address owner = fundMe.getOwner();

        vm.prank(owner);
        vm.expectRevert();
        fundMe.ownerWithdraw(0);
    }

    function testFuzz_WithdrawOnlyOnce(uint256 amount) public {
        amount = bound(amount, GOAL, 10 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        address owner = fundMe.getOwner();

        vm.startPrank(owner);

        fundMe.ownerWithdraw(0);

        vm.expectRevert(); // second withdraw should fail
        fundMe.ownerWithdraw(0);

        vm.stopPrank();
    }

    function testFuzz_WithdrawFeeMath(uint256 amount) public {
        amount = bound(amount, GOAL, 10 ether);

        vm.deal(USER, amount);

        vm.prank(USER);
        fundMe.fund{value: amount}();

        address owner = fundMe.getOwner();

        uint256 ownerBefore = owner.balance;
        uint256 feeBefore = FEE_RECIPIENT.balance;

        vm.prank(owner);
        fundMe.ownerWithdraw(0);

        uint256 expectedFee = (amount * PLATFORM_FEE_BPS) / BPS;
        uint256 expectedPayout = amount - expectedFee;

        uint256 ownerAfter = owner.balance;
        uint256 feeAfter = FEE_RECIPIENT.balance;

        assertEq(ownerAfter - ownerBefore, expectedPayout);
        assertEq(feeAfter - feeBefore, expectedFee);
    }
}
