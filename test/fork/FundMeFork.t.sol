//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";
import {FundFundMe, withdrawFundMe} from "../../script/Interactions.s.sol";

contract IntegrationTest is Test {
    FundMe fundMe;

    address USER = makeAddr("user");
    uint256 constant SEND_VALUE = 0.0025 ether;
    uint256 constant STARTING_BALANCE = 10 ether;
    uint256 constant GOAL = 5 ether;

    function setUp() external {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC"));

        DeployFundMe deploy = new DeployFundMe();
        fundMe = deploy.run();

        vm.deal(USER, STARTING_BALANCE);
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

    function testUserCanFundWithRealPriceFeed() public userFunded {
        uint256 funded = fundMe.getAddressToAmountFunded(USER);
        assertEq(funded, SEND_VALUE);
    }

    function testForkRevertsBelowMinUSD() public {
        vm.expectRevert();
        fundMe.fund{value: 0.000001 ether}();
    }

    function testForkOwnerCanWithdraw() public fullGoalFunded {
        address owner = fundMe.owner();

        vm.prank(owner);
        fundMe.ownerWithdraw(0);

        assertEq(address(fundMe).balance, 0);
    }

    function testForkPartialWithdrawWorks() public fullGoalFunded {
        address owner = fundMe.owner();
        uint256 withdrawAmount = 2 ether;

        vm.prank(owner);
        fundMe.ownerWithdraw(withdrawAmount);

        assertGt(address(fundMe).balance, 0);
    }

    function testForkMultipleUsersFunding() public {
        uint256 startingBalance = address(fundMe).balance;
        console.log("Initial balance:", address(fundMe).balance);
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        vm.deal(USER, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);

        vm.prank(USER);
        fundMe.fund{value: 0.0025 ether}();

        vm.prank(user2);
        fundMe.fund{value: 0.0035 ether}();

        vm.prank(user3);
        fundMe.fund{value: 0.0025 ether}();

        uint256 endingBalance = address(fundMe).balance;

        assertEq(endingBalance - startingBalance, 0.0085 ether);
    }

    function testForkPriceDropAffectsFunding() public {
        address priceFeed = address(fundMe.getPriceFeed());

        // simulate ETH price crash
        vm.mockCall(
            priceFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(0, int256(1000e8), 0, 0, 0) // ETH = $1000
        );

        vm.expectRevert();
        fundMe.fund{value: 0.0025 ether}(); // now below $5
    }

    function testFork_MEVLikeFundingRace() public userFunded {
        address attacker = makeAddr("attacker");

        vm.deal(attacker, 5 ether);

        // attacker funds first
        vm.prank(attacker);
        fundMe.fund{value: 0.03 ether}();

        // legit user tries after
        vm.prank(USER);
        fundMe.fund{value: 0.0025 ether}();

        // ensure system still consistent
        assertGt(address(fundMe).balance, 0);
    }

    function testForkWithdrawAfterManyFunders() public {
        address[] memory users = new address[](5);

        for (uint256 i = 0; i < 5; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            vm.deal(users[i], 0.0029 ether);

            vm.prank(users[i]);
            fundMe.fund{value: 0.0026 ether}();
        }

        uint256 amountToWithdraw = address(fundMe).balance;

        address owner = fundMe.owner();

        vm.prank(owner);
        vm.expectRevert();
        fundMe.ownerWithdraw(amountToWithdraw);

        assertEq(address(fundMe).balance, amountToWithdraw);
    }

    function testForkMultiplePartialWithdraws() public fullGoalFunded {
        address owner = fundMe.owner();

        vm.startPrank(owner);

        fundMe.ownerWithdraw(0.0025 ether);
        fundMe.ownerWithdraw(0.0023 ether);
        fundMe.ownerWithdraw(0.001 ether);

        vm.stopPrank();

        assertGt(address(fundMe).balance, 0);
    }

    function testForkWithdrawTwiceFailsOrSafe() public fullGoalFunded {
        address owner = fundMe.owner();

        vm.prank(owner);
        fundMe.ownerWithdraw(0);

        vm.prank(owner);
        vm.expectRevert();
        fundMe.ownerWithdraw(0); // should not break anything

        assertEq(address(fundMe).balance, 0);
    }

    function testForkRefundAfterDeadline() public userFunded {
        // move past deadline
        vm.warp(block.timestamp + 70);

        vm.prank(USER);
        fundMe.refund();

        assertEq(fundMe.getAddressToAmountFunded(USER), 0);
    }

    function testForkRefundFailsIfGoalReached() public fullGoalFunded {
        // bounce time forward past deadline
        vm.warp(block.timestamp + 8 days);

        vm.prank(USER);
        vm.expectRevert();
        fundMe.refund();
    }
}
