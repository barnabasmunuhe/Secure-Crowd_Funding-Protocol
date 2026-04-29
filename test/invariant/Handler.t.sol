// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FundMe} from "../../src/FundMe.sol";
import {Test} from "forge-std/Test.sol";

contract Handler is Test {
    FundMe public fundMe;

    address[] public users;
    uint256 public totalFunded;
    uint256 public totalWithdrawn;
    mapping(address => uint256) public userBalances;
    mapping(address => uint256) public totalRefunded;
    uint256 public totalPlatformFees;

    uint256 constant MIN = 0.0025 ether;

    constructor(FundMe _fundMe) {
        fundMe = _fundMe;

        // create some actors with
        users.push(makeAddr("user1"));
        users.push(makeAddr("user2"));
        users.push(makeAddr("user3"));
    }
    // ----------------------
    // ACTIONS (randomly called)
    // ----------------------

    function fund(uint256 amount, uint256 userIndex) public {
        address user = users[userIndex % users.length];

        amount = bound(amount, MIN, 5 ether);

        vm.deal(user, amount);

        vm.prank(user);
        try fundMe.fund{value: amount}() { //update state after success
            userBalances[user] += amount;
            totalFunded += amount;
        } catch {}
    }

    function refund(uint256 userIndex) public {
        address user = users[userIndex % users.length];

        vm.prank(user);
        try fundMe.refund() {
            uint256 amount = userBalances[user];

            if (amount > 0) {
                uint256 fee = (amount * fundMe.i_refundFeeBps()) / fundMe.BasisPoints();
                uint256 refundAmount = amount - fee;

                totalRefunded[user] += refundAmount;

                totalFunded -= amount; // decrease total funded by the full amount, fee is kept by contract
                totalPlatformFees += fee; // update total platform fees collected
                userBalances[user] = 0; // reset user balance after refund
            }
        } catch {}
    }

    function withdraw() public {
        address owner = fundMe.getOwner();
        uint256 balance = address(fundMe).balance;

        vm.prank(owner);
        try fundMe.ownerWithdraw(0) {
            uint256 fee = (balance * fundMe.i_platformFeeBps()) / 10_000;
            uint256 payout = balance - fee;

            totalWithdrawn += payout;
            totalPlatformFees += fee;

            totalFunded = 0; // reset total funded after withdrawal
        } catch {}
    }
}
