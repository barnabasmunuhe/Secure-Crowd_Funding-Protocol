//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {MockV3Aggregator} from 
"@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";contract FundMeTest is Test {
    FundMe public fundMe;
    MockV3Aggregator mockPriceFeed;

    address USER = makeAddr("user");
    address USER2 = makeAddr("user2");
    address FEE_RECIPIENT = makeAddr("feeRecipient");

    uint256 constant SEND_VALUE = 0.1 ether; //100000000000000000
    uint256 constant STARTING_BALANCE = 10 ether;
    uint256 constant GOAL = 5 ether;
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
    modifier funded() {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();
        _;
    }

    function testOnlyOwnerCanWithdrawFunds() public funded {
        vm.prank(USER);
        vm.expectRevert();
        fundMe.ownerWithdraw(SEND_VALUE);
    }

    function testWithdrawWorks() public funded{

        uint256 startingBalance = address(this).balance;

        fundMe.getState() = fundMe.FundMeState.SUCCESS;

        fundMe.ownerWithdraw(GOAL);

        uint256 endingBalance = address(this).balance;

        assertGt(endingBalance, startingBalance);
    }

    // // function testWithDrawWithASingleFunder() public funded {
    // //     // Arrange
    // //     uint256 startingOwnerBalance = fundMe.getOwner().balance;
    // //     uint256 startingFundMeBalance = address(fundMe).balance;

    // //     // Act
    // //     // uint256 gasStart = gasleft();//1000 //tells you how much gas is left in your tx call
    // //     vm.txGasPrice(GAS_PRICE);
    // //     vm.prank(fundMe.getOwner()); //c: 200
    // //     fundMe.ownerWithdraw(SEND_VALUE); // should have spend gas?

    // //     // uint256 gasEnd = gasleft();//800
    // //     // uint256 gasUsed = (gasStart - gasEnd) * tx.gasprice;
    // //     // console.log(gasUsed);

    // //     //  Assert
    // //     uint256 endingOwnerbalance = fundMe.getOwner().balance;
    // //     uint256 endingFundMeBalance = address(fundMe).balance;
    // //     assertEq(endingFundMeBalance, 0);
    // //     assertEq(startingFundMeBalance + startingOwnerBalance, endingOwnerbalance);
    // // }

    // function testwithdrawFromMultipleFunders() public funded {
    //     // Arrange
    //     uint160 numberOfFunders = 10;
    //     uint160 startingFunderIndex = 1;
    //     for (uint160 i = startingFunderIndex; i < numberOfFunders; i++) {
    //         //vm.prank new address
    //         //vm.deal new address
    //         //address()
    //         hoax(address(i), SEND_VALUE);
    //         fundMe.fund{value: SEND_VALUE}();
    //     }
    //     uint256 startingOwnerBalance = fundMe.getOwner().balance;
    //     uint256 startingFundMeBalance = address(fundMe).balance;

    //     // Act
    //     vm.startPrank(fundMe.getOwner());
    //     fundMe.ownerWithdraw(SEND_VALUE);
    //     vm.stopPrank();

    //     //assert
    //     assert(address(fundMe).balance == 0);
    //     assert(startingFundMeBalance + startingOwnerBalance == fundMe.getOwner().balance);
    // }

    // function testwithdrawFromMultipleFundersCheaper() public funded {
    //     // Arrange
    //     uint160 numberOfFunders = 10;
    //     uint160 startingFunderIndex = 1;
    //     for (uint160 i = startingFunderIndex; i < numberOfFunders; i++) {
    //         //vm.prank new address
    //         //vm.deal new address
    //         //address()
    //         hoax(address(i), SEND_VALUE);
    //         fundMe.fund{value: SEND_VALUE}();
    //     }
    //     uint256 startingOwnerBalance = fundMe.getOwner().balance;
    //     uint256 startingFundMeBalance = address(fundMe).balance;

    //     // Act
    //     vm.startPrank(fundMe.getOwner());
    //     fundMe.ownerWithdraw(SEND_VALUE);
    //     vm.stopPrank();

    //     //assert
    //     assert(address(fundMe).balance == 0);
    //     assert(startingFundMeBalance + startingOwnerBalance == fundMe.getOwner().balance);
    // }
}
