// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";

contract FundMeHandler is Test {
    FundMe public immutable fundMe;

    // Actors used by Foundry to interact with FundMe.
    address[] public users;

    // Ghost accounting: independent expected values.
    // handler must only update ghost variables after a successful transaction.
    uint256 public ghostTotalFunded;
    uint256 public ghostTotalRefunded;
    uint256 public ghostGrossWithdrawn;
    uint256 public ghostTotalOwnerPayout;
    uint256 public ghostTotalPlatformFees;

    // Per-user ghost accounting.
    mapping(address => uint256) public ghostOutstandingContribution;
    mapping(address => uint256) public ghostNetRefunded;

    uint256 public constant MINIMUM_ETH = 0.0025 ether;
    uint256 public constant MAX_FUNDING = 2 ether;

    constructor(FundMe _fundMe) {
        fundMe = _fundMe;

        users.push(makeAddr("user1"));
        users.push(makeAddr("user2"));
        users.push(makeAddr("user3"));

        // Give each actor enough ETH to interact with FundMe.
        for (uint256 i; i < users.length; i++) {
            vm.deal(users[i], 100 ether);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            HANDLER ACTIONS
    //////////////////////////////////////////////////////////////*/

    function fund(uint256 amount, uint256 userIndex) public {
        // Funding is only possible while the campaign is active.
        if (fundMe.getState() != FundMe.FundMeState.ACTIVE) return;

        if (block.timestamp >= fundMe.getDeadline()) return;

        address user = users[userIndex % users.length];

        amount = bound(amount, MINIMUM_ETH, MAX_FUNDING);

        // Ensure the actor has enough ETH.
        vm.deal(user, 100 ether);

        vm.prank(user);

        try fundMe.fund{value: amount}() {
            // Update ghost accounting only after successful funding.
            ghostTotalFunded += amount;
            ghostOutstandingContribution[user] += amount;
        } catch {}
    }

    function refund(uint256 userIndex) public {
        address user = users[userIndex % users.length];

        uint256 amount = ghostOutstandingContribution[user];

        if (amount == 0) return;

        vm.prank(user);

        try fundMe.refund() {
            uint256 fee = (amount * fundMe.i_refundFeeBps()) / fundMe.BASIS_POINTS();

            uint256 netRefund = amount - fee;

            // Track gross refunded principal.
            ghostTotalRefunded += amount;

            // Track the user's actual net refund.
            ghostNetRefunded[user] += netRefund;

            // Track accumulated platform fees.
            ghostTotalPlatformFees += fee;

            // The user's contribution has been refunded.
            ghostOutstandingContribution[user] = 0;
        } catch {}
    }

    function withdraw(uint256 amount) public {
        if (fundMe.getState() != FundMe.FundMeState.SUCCESS) return;

        uint256 balance = address(fundMe).balance;

        if (balance == 0) return;

        // Zero means withdraw the entire remaining balance.
        if (amount != 0) {
            amount = bound(amount, 1, balance);
        }

        uint256 amountToWithdraw = amount == 0 ? balance : amount;

        address owner = fundMe.getOwner();

        vm.prank(owner);

        try fundMe.ownerWithdraw(amount) {
            uint256 fee = (amountToWithdraw * fundMe.i_platformFeeBps()) / fundMe.BASIS_POINTS();

            uint256 payout = amountToWithdraw - fee;

            // Track gross ETH removed from FundMe.
            ghostGrossWithdrawn += amountToWithdraw;

            // Track the owner's actual net payout.
            ghostTotalOwnerPayout += payout;

            // Track platform fees.
            ghostTotalPlatformFees += fee;
        } catch {}
    }

    function finalizeCampaign() public {
        if (fundMe.getState() != FundMe.FundMeState.ACTIVE) return;

        if (block.timestamp < fundMe.getDeadline()) return;

        try fundMe.finalizeCampaign() {} catch {}
    }

    function warpToDeadline() public {
        vm.warp(fundMe.getDeadline());
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getUsers() public view returns (address[] memory) {
        return users;
    }

    function usersLength() public view returns (uint256) {
        return users.length;
    }

    function getUser(uint256 index) public view returns (address) {
        return users[index];
    }
}
