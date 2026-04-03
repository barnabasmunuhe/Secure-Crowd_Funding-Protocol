// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

error FundMe__NotOwner();
error FundMe__SpendMoreEth();
error FundMe__WithdrawFailed();
error FundMe__NoFundsToWithdraw();
error FundMe__DeadlineNotYetPleaseWait();
error FundMe__NoRefundGoalIsMet();
error FundMe__NotSuccessful();
error FundMe__goalReached();
error FundMe__NotActive();
error FundMe__InsufficientBalance();

contract FundMe is Ownable, ReentrancyGuard {
    using PriceConverter for uint256;

        /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    enum FundMeState {
        ACTIVE,//funding ongoing, not yet reached the goal
        SUCCESS,// goal has been reached, owner can withdraw funds
        FAILED // deadline has passed without reaching the goal
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address funder => uint256 amount) private s_addressToAmountFunded;
    address payable[] private s_funders;
    uint256 private s_totalAmountFunded;
    uint256 private s_totalWithdrawn;


    uint256 public constant MINIMUM_USD = 1e18; // 1 dollars
    AggregatorV3Interface private s_priceFeed;
    FundMeState private s_state;

    uint256 public immutable i_goal; // 50_000 * 1e18 (USD, 18 decimals)
    uint256 public immutable i_deadline; 


    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Funded(address indexed funder, uint256 amount);
    event OwnerWithdrawn(address indexed owner, uint256 balance);
    event Refunded(address indexed user, uint256 amount, uint256 fee);


    constructor(address priceFeed, uint256 goal) Ownable(msg.sender) {
        s_priceFeed = AggregatorV3Interface(priceFeed);
        i_deadline = block.timestamp + 30 days;
        i_goal = goal;
        s_state = FundMeState.ACTIVE;
    }

        /*//////////////////////////////////////////////////////////////
                         FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function fund() public payable {
    if (s_state != FundMeState.ACTIVE) {
        revert FundMe__NotActive();
    }

        uint256 usdAmount = msg.value.getConversionRate(s_priceFeed);
        if (usdAmount < MINIMUM_USD) {
            revert FundMe__SpendMoreEth();
        }

        if (s_addressToAmountFunded[msg.sender] == 0) {
            // 0 = funder has never funded before
            s_funders.push(payable(msg.sender));
        }

        s_addressToAmountFunded[msg.sender] += msg.value;
        s_totalAmountFunded += msg.value;

        if (s_totalAmountFunded >= i_goal) {
            s_state = FundMeState.SUCCESS;
        }

        emit Funded(msg.sender, msg.value);
    }

    function refund() external nonReentrant {
        // Checks
    if (block.timestamp < i_deadline) { // one can only refund after the deadline has passed and goal not reached
        revert FundMe__DeadlineNotYetPleaseWait();
    }

    if (s_totalAmountFunded >= i_goal) {// if the goal is reached, the users should not be able to refund
        revert FundMe__NoRefundGoalIsMet();
    }

    uint256 amount = s_addressToAmountFunded[msg.sender];
    if (amount == 0) {
        revert FundMe__NoFundsToWithdraw();
    }

    // Effects
    s_addressToAmountFunded[msg.sender] = 0;// making sure that if the user calls refund again, it will fail the "NoFundsToWithdraw" check

    // Interaction
    (bool success,) = payable(msg.sender).call{value: amount}("");
    if(!success) {
        revert FundMe__WithdrawFailed();
    }

    emit Refunded(msg.sender, amount, 0);
}

    function ownerWithdraw(uint256 amount) external onlyOwner nonReentrant {
        // checks
    if(s_state != FundMeState.SUCCESS) {
        revert FundMe__NotSuccessful(); // goal not reached so owner CANNOT withdraw
    }
    uint256 balance = address(this).balance;
    if(balance == 0) {
        revert FundMe__NoFundsToWithdraw();
    }

    // effects
    uint256 amountToWithdraw = amount;
    if(amount == 0) {
        amountToWithdraw = balance; // withdraw the entire balance if the owner passes 0 as the amount
    }
    else {
        if (amount > balance) {
            revert FundMe__InsufficientBalance(); // goal reached but not enough funds to withdraw the requested amount
        }
    }
    s_totalWithdrawn += amountToWithdraw; // tracking the total withdrawn amount by the owner, can be used for analytics or to set a max withdraw limit in the future

    // interaction
    (bool success,) = payable(msg.sender).call{value: amountToWithdraw}("");
    if (!success) {
        revert FundMe__WithdrawFailed();
    }

    emit OwnerWithdrawn(msg.sender, amountToWithdraw);
}

    // Explainer from: https://solidity-by-example.org/fallback/
    // Ether is sent to contract
    //      is msg.data empty?
    //          /   \
    //         yes  no
    //         /     \
    //    receive()?  fallback()
    //     /   \
    //   yes   no
    //  /        \
    //receive()  fallback()

    fallback() external payable {
        fund();
    }

    receive() external payable {
        fund();
    }

    /**
     * View / Pure functions (Getters)
     */
    function getVersion() public view returns (uint256) {
        return s_priceFeed.version();
    }

    function getAddressToAmountFunded(address fundingAddress) external view returns (uint256) {
        return s_addressToAmountFunded[fundingAddress];
    }

    function getFunder(uint256 index) external view returns (address) {
        return s_funders[index];
    }

    function getOwner() external view returns (address) {
        return msg.sender;
    }
}

// Concepts we didn't cover yet (will cover in later sections)
// 1. Enum
// 2. Events
// 3. Try / Catch
// 4. Function Selector
// 5. abi.encode / decode
// 6. Hash with keccak256
// 7. Yul / Assembly
