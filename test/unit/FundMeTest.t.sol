// //SPDX-License-Identifier: MIT

// pragma solidity ^0.8.28;

// import {Test, console} from "forge-std/Test.sol";
// import {FundMe} from "../../src/FundMe.sol";
// import {DeployFundMe} from "../../script/DeployFundMe.s.sol";

// contract FundMeTest is Test {
//     FundMe fundMe;

//     address USER = makeAddr("user"); // creating a dummy address for user
//     uint256 constant SEND_VALUE = 0.1 ether; //100000000000000000
//     uint256 constant STARTING_BALANCE = 10 ether;
//     uint256 constant GAS_PRICE = 1;

//     function setUp() external {
//         // us -> FundMeTest -> FundMe
//         //fundMe = new FundMe(0x694AA1769357215DE4FAC081bf1f309aDC325306);
//         DeployFundMe deployFundMe = new DeployFundMe();
//         fundMe = deployFundMe.run();
//         vm.deal(USER, STARTING_BALANCE); //gives the USER a starting balance
//     } // always runs first

//     function testMinimumDollarIsFive() public view {
//         assertEq(fundMe.MINIMUM_USD(), 5e18);
//     } //then this

//     function testOwnerIsMSgSender() public view {
//         assertEq(fundMe.getOwner(), msg.sender);
//     } //then this

//     //What can we do to work with addresses outside our system?(Types of tests)
//     // 1. Unit
//     // -Testing a specific part of our code
//     // 2. Integration
//     // -Testing how our code works with other parts of our code
//     // 3. Forked
//     // -Testing our code on simulated real environment
//     // 4. Staging
//     // -Testing our code on a real environment

//     function testPriceFeedVersionIsAccurate() public view {
//         if (block.chainid == 11155111) {
//             uint256 version = fundMe.getVersion();
//             assertEq(version, 4);
//         } else if (block.chainid == 1) {
//             uint256 version = fundMe.getVersion();
//             assertEq(version, 6);
//         }
//     }

//     function testFundFailsWithoutEnoughETH() public {
//         vm.expectRevert(); //hey,the next line should revert!
//         //assert(This tx fails /reverts)
//         fundMe.fund(); //send 0 value
//     }

//     function testFundUpdatesFundedDataStructure() public {
//         vm.prank(USER); // The next tx will be sent by USER
//         fundMe.fund{value: SEND_VALUE}();

//         uint256 amountFunded = fundMe.getAddressToAmountFunded(USER);
//         assertEq(amountFunded, SEND_VALUE);
//     }

//     function testAddsFunderToArrayOfFunders() public {
//         vm.prank(USER);
//         fundMe.fund{value: SEND_VALUE}();

//         address funder = fundMe.getFunder(0);
//         assertEq(funder, USER);
//     }

//     modifier funded() {
//         vm.prank(USER);
//         fundMe.fund{value: SEND_VALUE}();
//         _;
//     }

//     function testOnlyOwnerCanWithdrawFunds() public funded {
//         vm.prank(USER);
//         fundMe.fund{value: SEND_VALUE}();

//         vm.prank(USER);
//         vm.expectRevert();
//         fundMe.ownerWithdraw(SEND_VALUE);
//     }

//     function testWithDrawWithASingleFunder() public funded {
//         // Arrange
//         uint256 startingOwnerBalance = fundMe.getOwner().balance;
//         uint256 startingFundMeBalance = address(fundMe).balance;

//         // Act
//         // uint256 gasStart = gasleft();//1000 //tells you how much gas is left in your tx call
//         vm.txGasPrice(GAS_PRICE);
//         vm.prank(fundMe.getOwner()); //c: 200
//         fundMe.ownerWithdraw(SEND_VALUE); // should have spend gas?

//         // uint256 gasEnd = gasleft();//800
//         // uint256 gasUsed = (gasStart - gasEnd) * tx.gasprice;
//         // console.log(gasUsed);

//         //  Assert
//         uint256 endingOwnerbalance = fundMe.getOwner().balance;
//         uint256 endingFundMeBalance = address(fundMe).balance;
//         assertEq(endingFundMeBalance, 0);
//         assertEq(startingFundMeBalance + startingOwnerBalance, endingOwnerbalance);
//     }

//     function testwithdrawFromMultipleFunders() public funded {
//         // Arrange
//         uint160 numberOfFunders = 10;
//         uint160 startingFunderIndex = 1;
//         for (uint160 i = startingFunderIndex; i < numberOfFunders; i++) {
//             //vm.prank new address
//             //vm.deal new address
//             //address()
//             hoax(address(i), SEND_VALUE);
//             fundMe.fund{value: SEND_VALUE}();
//         }
//         uint256 startingOwnerBalance = fundMe.getOwner().balance;
//         uint256 startingFundMeBalance = address(fundMe).balance;

//         // Act
//         vm.startPrank(fundMe.getOwner());
//         fundMe.ownerWithdraw(SEND_VALUE);
//         vm.stopPrank();

//         //assert
//         assert(address(fundMe).balance == 0);
//         assert(startingFundMeBalance + startingOwnerBalance == fundMe.getOwner().balance);
//     }

//     function testwithdrawFromMultipleFundersCheaper() public funded {
//         // Arrange
//         uint160 numberOfFunders = 10;
//         uint160 startingFunderIndex = 1;
//         for (uint160 i = startingFunderIndex; i < numberOfFunders; i++) {
//             //vm.prank new address
//             //vm.deal new address
//             //address()
//             hoax(address(i), SEND_VALUE);
//             fundMe.fund{value: SEND_VALUE}();
//         }
//         uint256 startingOwnerBalance = fundMe.getOwner().balance;
//         uint256 startingFundMeBalance = address(fundMe).balance;

//         // Act
//         vm.startPrank(fundMe.getOwner());
//         fundMe.ownerWithdraw(SEND_VALUE);
//         vm.stopPrank();

//         //assert
//         assert(address(fundMe).balance == 0);
//         assert(startingFundMeBalance + startingOwnerBalance == fundMe.getOwner().balance);
//     }
// }
