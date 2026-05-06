// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {FundMe} from "../../src/FundMe.sol";
import {Test} from "forge-std/Test.sol";

contract Handler is Test {
    FundMe public fundMe;

    address[] public users;
    // shadow accounting variables to track expected state
    uint256 public totalFunded;
    uint256 public totalWithdrawn;
    uint256 public totalPlatformFees;

    mapping(address => uint256) public userBalances;
    mapping(address => uint256) public totalRefunded;

    uint256 constant MIN = 0.0025 ether;
    uint256 public constant BasisPoints = 10_000; // 100% in basis points, used for fee calculations to avoid floating point issues

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
        address user = users[userIndex % users.length]; //multi user simulation

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

    function withdraw(uint256 amount) public {
        address owner = fundMe.getOwner();
        uint256 balance = address(fundMe).balance;

        // Nothing to withdraw
        if (balance == 0) revert FundMe.FundMe__NoFundsToWithdraw();

        // allow partial OR full withdraw (0 means full withdrawal)
        amount = bound(amount, 0, balance);

        vm.prank(owner);
        try fundMe.ownerWithdraw(amount) {
            totalWithdrawn = amount == 0 ? balance : amount; //if withdraw amount is 0, withdraw full balance, otherwise withdraw specified amount

            uint256 fee = (totalWithdrawn * fundMe.i_platformFeeBps()) / BasisPoints;
            uint256 payout = totalWithdrawn - fee;

            totalWithdrawn += payout;
            totalPlatformFees += fee;

            if (totalFunded >= totalWithdrawn) {
                totalFunded -= totalWithdrawn; // decrease total funded by the withdrawn amount, fee is kept by contract
            } else {
                totalFunded = 0;
            }
        } catch {}
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
}
