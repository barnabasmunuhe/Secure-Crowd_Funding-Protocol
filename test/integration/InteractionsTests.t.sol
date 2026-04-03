// //SPDX-License-Identifier: MIT

// pragma solidity ^0.8.28;

// import {Test, console} from "forge-std/Test.sol";
// import {FundMe} from "../../src/FundMe.sol";
// import {DeployFundMe} from "../../script/DeployFundMe.s.sol";
// import {FundFundMe, withdrawFundMe} from "../../script/Interactions.s.sol";

// contract IntegrationTest is Test {
//     FundMe fundMe;

//     address USER = makeAddr("user");
//     uint256 constant SEND_VALUE = 10 ether; //100000000000000000
//     uint256 constant STARTING_BALANCE = 0.03 ether;
//     uint256 constant GAS_PRICE = 1;

//     function setUp() external {
//         DeployFundMe deploy = new DeployFundMe();
//         fundMe = deploy.run();
//         vm.deal(USER, STARTING_BALANCE);
//     }

//     function testUserCanFundInteractions() public {
//         FundFundMe fundFundMe = new FundFundMe();

//         address funderContract = address(fundFundMe);
//         vm.deal(funderContract, SEND_VALUE); // fund the contract

//         fundFundMe.fundFundMe(address(fundMe)); //contract sends ETH

//         withdrawFundMe WithdrawContract = new withdrawFundMe();
//         WithdrawContract.withdrawfundMe(address(fundMe));

//         assert(address(fundMe).balance == 0);
//     }
// }
