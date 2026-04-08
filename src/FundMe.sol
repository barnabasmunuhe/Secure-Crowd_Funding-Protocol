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
error FundMe__NotSuccessful();
error FundMe__goalReached();
error FundMe__NotActive();
error FundMe__InsufficientBalance();
error FundMe__RefundFailed();

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
    uint256 private s_totalWithdrawnByOwner;
    uint256 private s_platformFeesCollected;
    AggregatorV3Interface private s_priceFeed;
    FundMeState private s_state;

    uint256 public constant MINIMUM_USD = 1e18; // 1 dollars
    uint256 public constant BasisPoints = 10_000; // 100% in basis points, used for fee calculations to avoid floating point issues

    uint256 public immutable i_goal; // 50_000 * 1e18 (USD, 18 decimals)
    uint256 public immutable i_deadline; 
    address public immutable i_feeRecipient; // can be a company wallet,multSig wallet or DAO treasury that will receive a percentage of the funds if the funding campaign fails
    uint256 public immutable i_platformFeeBps;
    uint256 public immutable i_refundFeeBps;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Funded(address indexed funder, uint256 amount);
    event OwnerWithdrawn(address indexed owner, uint256 balance);
    event Refunded(address indexed user, uint256 amount, uint256 fee);


    constructor(address priceFeed, uint256 goal, address feeRecipient, uint256 platformFeeBps, uint256 refundFeeBps) Ownable(msg.sender) {
        s_priceFeed = AggregatorV3Interface(priceFeed);
        i_deadline = block.timestamp + 30 days;
        i_goal = goal;

        i_feeRecipient = feeRecipient;
        i_platformFeeBps = platformFeeBps;
        i_refundFeeBps = refundFeeBps;
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
    if(s_state == FundMeState.SUCCESS) {
        revert FundMe__goalReached(); // if the goal is reached, the users should not be able to refund
    }


    if(s_state == FundMeState.ACTIVE && block.timestamp < i_deadline) {
        revert FundMe__DeadlineNotYetPleaseWait(); // if the funding is still active and the deadline has not yet passed, users should not be able to refund
    }

    uint256 amount = s_addressToAmountFunded[msg.sender];
    if (amount == 0) {
        revert FundMe__NoFundsToWithdraw();
    }

        // Effects
    s_addressToAmountFunded[msg.sender] = 0;// making sure that if the user calls refund again, it will fail the "NoFundsToWithdraw" check
    //Fee calculation
    uint256 fee = (amount * i_refundFeeBps) / BasisPoints;
    uint256 refundAmount = amount - fee;

    // tracking
    s_platformFeesCollected += fee; // tracking the total fees collected by the platform


        // Interaction
    (bool refunding,) = payable(i_feeRecipient).call{value: fee}("");
    if(!refunding) {
        revert FundMe__RefundFailed(); // if fee transfer fails, we revert the entire transaction to ensure the user does not receive a refund without paying the fee
    }

    (bool success,) = payable(msg.sender).call{value: amount}("");
    if(!success) {
        revert FundMe__WithdrawFailed();
    }

    emit Refunded(msg.sender, refundAmount, fee);
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
        // Fee Calculation
        uint256 fee = (amountToWithdraw * i_platformFeeBps) / BasisPoints;
        uint256 payoutAmount = amountToWithdraw - fee;
        // tracking
    s_totalWithdrawnByOwner += payoutAmount; // tracking the total withdrawn amount by the owner, can be used for analytics or to set a max withdraw limit in the future
    s_platformFeesCollected += fee; // tracking the total fees collected by the platform, can be used for analytics or to set a max fee limit in the future

    // interaction
    (bool feeTransferSuccess,) = payable(i_feeRecipient).call{value: fee}("");
    if (!feeTransferSuccess) {
        revert FundMe__WithdrawFailed(); // if fee transfer fails, we revert the entire transaction to ensure the owner does not receive funds without paying the fee
    }

    (bool success,) = payable(msg.sender).call{value: payoutAmount}("");
    if (!success) {
        revert FundMe__WithdrawFailed();
    }

    emit OwnerWithdrawn(msg.sender, payoutAmount);
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

    function getTotalAmountFunded() external view returns (uint256) {
        return s_totalAmountFunded;
    }

    function getState() external view returns (FundMeState) {
        return s_state;
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
