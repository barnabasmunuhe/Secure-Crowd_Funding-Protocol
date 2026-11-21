//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {FundMe} from "../../src/FundMe.sol";
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";
import {FundFundMe, withdrawFundMe} from "../../script/Interactions.s.sol";

contract FundMeFork is Test {
    FundMe fundMe;

    address USER = makeAddr("user");
    uint256 constant SEND_VALUE = 0.005 ether;
    uint256 constant STARTING_BALANCE = 20 ether;
    uint256 constant GOAL = 5 ether; // $10000 usd

    function setUp() external {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));

        DeployFundMe deploy = new DeployFundMe();
        fundMe = deploy.run();

        vm.deal(USER, STARTING_BALANCE);
    }

    // Calculates the ETH required to exceed the USD goal by 10%.
    function _goalFundingAmount() internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(fundMe.getPriceFeed());

        (, int256 answer,,,) = priceFeed.latestRoundData();

        require(answer > 0, "Invalid ETH/USD price");

        uint256 requiredWei = (fundMe.i_goalUsd() * 1e8) / uint256(answer);

        return (requiredWei * 110) / 100 + 1;
    }

    // Calculates the minimum ETH contribution using the live Chainlink price.
    function _minimumFundingAmount() internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(fundMe.getPriceFeed());

        (, int256 answer,,,) = priceFeed.latestRoundData();

        require(answer > 0, "Invalid ETH/USD price");

        uint256 requiredWei = (fundMe.i_minimumUsd() * 1e8) / uint256(answer);

        return requiredWei + 1;
    }

    modifier userFunded() {
        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();
        _;
    }

    modifier fullGoalFunded() {
        vm.prank(USER);
        fundMe.fund{value: _goalFundingAmount()}();
        _;
    }

    // --------------------------------------------------
    // FUNDING
    // --------------------------------------------------

    function testUserCanFundWithRealPriceFeed() public userFunded {
        assertEq(fundMe.getAddressToAmountFunded(USER), SEND_VALUE);
    }

    function testForkRevertsBelowMinUSD() public {
        vm.expectRevert(FundMe.FundMe__SpendMoreEth.selector);

        fundMe.fund{value: 0.000001 ether}();
    }

    function testForkMultipleUsersFunding() public {
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        vm.deal(USER, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);

        uint256 startingBalance = address(fundMe).balance;

        vm.prank(USER);
        fundMe.fund{value: 0.005 ether}();

        vm.prank(user2);
        fundMe.fund{value: 0.006 ether}();

        vm.prank(user3);
        fundMe.fund{value: 0.005 ether}();

        uint256 endingBalance = address(fundMe).balance;

        assertEq(endingBalance - startingBalance, 0.016 ether);
    }

    function testForkPriceDropAffectsFunding() public {
        address priceFeed = address(fundMe.getPriceFeed());

        // simulate ETH price crash
        vm.mockCall(
            priceFeed,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(uint80(1), int256(1000e8), block.timestamp, block.timestamp, uint80(1)) // ETH = $1000
        );

        vm.expectRevert(FundMe.FundMe__SpendMoreEth.selector);
        fundMe.fund{value: 0.0025 ether}(); // now below $5
    }

    function testMultipleContributorsCanFundSequentially() public userFunded {
        address attacker = makeAddr("attacker");

        vm.deal(attacker, 5 ether);

        vm.prank(attacker);
        fundMe.fund{value: 0.03 ether}();

        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();

        assertGt(address(fundMe).balance, 0);
    }

    function testForkFundingUpdatesTotalAmountFunded() public userFunded {
        assertEq(fundMe.getTotalAmountFunded(), SEND_VALUE);
    }

    function testForkFundingUpdatesUsdAccounting() public userFunded {
        assertGt(fundMe.getTotalAmountFundedUsd(), 0);
    }

    function testForkFundingEmitsCorrectEvent() public {
        vm.expectEmit(true, false, false, true, address(fundMe));
        emit FundMe.Funded(USER, SEND_VALUE);

        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();
    }

    function testForkSameContributorCanFundMultipleTimes() public {
        vm.startPrank(USER);

        fundMe.fund{value: SEND_VALUE}();
        fundMe.fund{value: SEND_VALUE}();

        vm.stopPrank();

        assertEq(fundMe.getAddressToAmountFunded(USER), SEND_VALUE * 2);

        assertEq(fundMe.getTotalAmountFunded(), SEND_VALUE * 2);
    }

    function testForkFundingAfterDeadlineReverts() public {
        vm.warp(fundMe.getDeadline() + 1);

        vm.expectRevert(FundMe.FundMe__CampaignEnded.selector);

        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();
    }

    function testForkFundingAfterGoalReachedReverts() public fullGoalFunded {
        assertEq(uint256(fundMe.getState()), uint256(FundMe.FundMeState.SUCCESS));

        vm.expectRevert(FundMe.FundMe__NotActive.selector);

        vm.prank(USER);
        fundMe.fund{value: SEND_VALUE}();
    }

    // --------------------------------------------------
    // SUCCESSFUL CAMPAIGN / WITHDRAWALS
    // --------------------------------------------------
    function testForkOwnerCanWithdraw() public fullGoalFunded {
        vm.prank(fundMe.owner());
        fundMe.ownerWithdraw(0);

        assertEq(address(fundMe).balance, 0);
    }

    function testForkPartialWithdrawWorks() public fullGoalFunded {
        uint256 withdrawAmount = 2 ether;

        vm.prank(fundMe.owner());
        fundMe.ownerWithdraw(withdrawAmount);

        assertGt(address(fundMe).balance, 0);
    }

    function testForkMultiplePartialWithdraws() public fullGoalFunded {
        vm.startPrank(fundMe.owner());

        fundMe.ownerWithdraw(0.0025 ether);
        fundMe.ownerWithdraw(0.0023 ether);
        fundMe.ownerWithdraw(0.001 ether);

        vm.stopPrank();

        assertGt(address(fundMe).balance, 0);
    }

    function testForkWithdrawAfterManyFunders() public {
        uint256 initialBalance = address(fundMe).balance;
        uint256 contribution = (_goalFundingAmount() + 2) / 3;

        address[] memory contributors = new address[](3);

        for (uint256 i = 0; i < contributors.length; i++) {
            contributors[i] = makeAddr(string(abi.encodePacked("contributor", i)));

            vm.deal(contributors[i], contribution);

            vm.prank(contributors[i]);
            fundMe.fund{value: contribution}();

            assertEq(fundMe.getAddressToAmountFunded(contributors[i]), contribution);
        }

        assertEq(uint256(fundMe.getState()), uint256(FundMe.FundMeState.SUCCESS));

        assertEq(address(fundMe).balance, initialBalance + contribution * 3);

        address owner = fundMe.owner();

        vm.prank(owner);
        fundMe.ownerWithdraw(0);

        assertEq(address(fundMe).balance, 0);
    }

    function testForkWithdrawTwiceFails() public fullGoalFunded {
        address owner = fundMe.owner();

        // First withdrawal: withdraw everything.
        vm.prank(owner);
        fundMe.ownerWithdraw(0);

        assertEq(address(fundMe).balance, 0);

        // Second withdrawal: must revert because no funds remain.
        vm.expectRevert(FundMe.FundMe__NoFundsToWithdraw.selector);

        vm.prank(owner);
        fundMe.ownerWithdraw(0);
    }

    function testOwnerCannotWithdrawBeforeGoalReached() public {
        address[] memory users = new address[](5);

        for (uint256 i = 0; i < users.length; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));

            vm.deal(users[i], 1 ether);

            vm.prank(users[i]);
            fundMe.fund{value: SEND_VALUE}();
        }

        uint256 balanceBefore = address(fundMe).balance;

        address owner = fundMe.owner();

        vm.expectRevert(FundMe.FundMe__NotSuccessful.selector);

        vm.prank(owner);
        fundMe.ownerWithdraw(0);

        assertEq(address(fundMe).balance, balanceBefore);
    }

    function testForkPartialWithdrawalUpdatesAccounting() public fullGoalFunded {
        uint256 amount = 0.5 ether;

        uint256 expectedFee = (amount * fundMe.i_platformFeeBps()) / fundMe.BASIS_POINTS();

        uint256 expectedPayout = amount - expectedFee;

        address owner = fundMe.owner();
        address feeRecipient = fundMe.i_feeRecipient();

        uint256 ownerBalanceBefore = owner.balance;
        uint256 recipientBalanceBefore = feeRecipient.balance;
        uint256 balanceBeforeWithdrawal = address(fundMe).balance;

        vm.prank(owner);
        fundMe.ownerWithdraw(amount);

        assertEq(owner.balance - ownerBalanceBefore, expectedPayout);

        assertEq(feeRecipient.balance - recipientBalanceBefore, expectedFee);

        assertEq(fundMe.getTotalWithdrawnByOwner(), expectedPayout);

        assertEq(fundMe.getPlatformFeesCollected(), expectedFee);

        assertEq(address(fundMe).balance, balanceBeforeWithdrawal - amount);
    }

    function testForkNonOwnerCannotWithdraw() public fullGoalFunded {
        address unauthorized = makeAddr("unauthorized");

        vm.expectRevert();

        vm.prank(unauthorized);
        fundMe.ownerWithdraw(0);
    }

    function testForkCannotWithdrawMoreThanContractBalance() public fullGoalFunded {
        uint256 contractBalance = address(fundMe).balance;
        address owner = fundMe.owner();

        vm.expectRevert(FundMe.FundMe__InsufficientBalance.selector);
        vm.prank(owner);
        fundMe.ownerWithdraw(contractBalance + 1);
    }

    // --------------------------------------------------
    // UNSUCCESSFUL CAMPAIGN / REFUNDS
    // --------------------------------------------------
    function testForkRefundAfterDeadline() public userFunded {
        // move past deadline
        vm.warp(fundMe.getDeadline() + 1);

        vm.prank(USER);
        fundMe.refund();

        assertEq(fundMe.getAddressToAmountFunded(USER), 0);
    }

    function testForkRefundFailsIfGoalReached() public fullGoalFunded {
        assertEq(uint256(fundMe.getState()), uint256(FundMe.FundMeState.SUCCESS));

        vm.expectRevert(FundMe.FundMe__GoalReached.selector);

        vm.prank(USER);
        fundMe.refund();
    }

    function testForkRefundDeductsCorrectFee() public userFunded {
        uint256 contribution = fundMe.getAddressToAmountFunded(USER);
        uint256 expectedFee = (contribution * fundMe.i_refundFeeBps()) / fundMe.BASIS_POINTS();

        uint256 expectedRefund = contribution - expectedFee;

        address feeRecipient = fundMe.i_feeRecipient();

        uint256 recipientBalanceBefore = feeRecipient.balance;

        uint256 balanceBeforeRefund = address(fundMe).balance;

        vm.warp(fundMe.getDeadline() + 1);

        vm.prank(USER);
        fundMe.refund();

        assertEq(feeRecipient.balance - recipientBalanceBefore, expectedFee);

        assertEq(fundMe.getPlatformFeesCollected(), expectedFee);

        assertEq(fundMe.getAddressToAmountFunded(USER), 0);

        assertEq(address(fundMe).balance, balanceBeforeRefund - contribution);

        // The user receives the contribution minus the refund fee.
        assertEq(expectedRefund + expectedFee, contribution);
    }

    function testForkCannotRefundTwice() public userFunded {
        vm.warp(fundMe.getDeadline() + 1);

        vm.prank(USER);
        fundMe.refund();

        vm.expectRevert(FundMe.FundMe__NoFundsToWithdraw.selector);

        vm.prank(USER);
        fundMe.refund();
    }

    function testForkFinalizeCampaignAfterDeadline() public userFunded {
        vm.warp(fundMe.getDeadline() + 1);

        fundMe.finalizeCampaign();

        assertEq(uint256(fundMe.getState()), uint256(FundMe.FundMeState.FAILED));
    }

    function testForkCannotFinalizeCampaignTwice() public userFunded {
        vm.warp(fundMe.getDeadline() + 1);

        fundMe.finalizeCampaign();

        vm.expectRevert(FundMe.FundMe__CampaignAlreadyFinalized.selector);

        fundMe.finalizeCampaign();
    }
}
