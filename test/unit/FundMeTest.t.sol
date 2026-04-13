//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract FundMeTest is Test {
    FundMe public fundMe;
    MockV3Aggregator mockPriceFeed;

    receive() external payable {} // to make the test contract receive ETH

    address USER = makeAddr("user");
    address USER2 = makeAddr("user2");
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
    }

    // constructor function tests
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

    // Funding Tests

    // function testPriceFeedVersionIsAccurate() public view {
    //     if (block.chainid == 11155111) {
    //         uint256 version = fundMe.getVersion();
    //         assertEq(version, 4);
    //     } else if (block.chainid == 1) {
    //         uint256 version = fundMe.getVersion();
    //         assertEq(version, 6);
    //     }
    // }

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

    function testOnlyOwnerCanWithdrawFunds() public userFunded {
        vm.prank(USER);
        vm.expectRevert();
        fundMe.ownerWithdraw(GOAL);
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

    function testWithdrawWorksWithFullSystemLogic() public fullGoalFunded{
        // Arrage 
    uint256 contractBalanceBefore = address(fundMe).balance;
    uint256 ownerBalanceBefore = address(this).balance;
    uint256 feeRecipientBalanceBefore = address(FEE_RECIPIENT).balance;

        // Act
        fundMe.ownerWithdraw(0);//full withdraw

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

    function testWithdrawExactFeeAndPayout() public fullGoalFunded{
        // Arrange
        uint256 contractBalanceBefore = address(fundMe).balance;
        uint256 feeRecipientBalanceBefore = address(FEE_RECIPIENT).balance;
        
        // Act
        fundMe.ownerWithdraw(0);

        // Assert
        uint256 contractBalanceAfter = address(fundMe).balance;
        uint256 feeRecipientBalanceAfter = address(FEE_RECIPIENT).balance;

        // fee calculation
        uint256 expectedFee = (contractBalanceBefore * PLATFORM_FEE_BPS)/BPS;

        // fee received
        uint256 actualFee = feeRecipientBalanceAfter - feeRecipientBalanceBefore;
        
        // fee exact?
        assertEq(expectedFee,actualFee);

        // contract drained?
        assertEq(contractBalanceAfter, 0);

        // is fee + payout = total balance?
        uint256 payout = contractBalanceBefore - expectedFee; 

        assertEq(payout + actualFee, contractBalanceBefore);
    }

    
}
