// // Layout of Contract:
// // version
// // imports
// // errors
// // interfaces, libraries, contracts
// // Type declarations
// // State variables
// // Events
// // Modifiers
// // Functions

// // Layout of Functions:
// // constructor
// // receive function (if exists)
// // fallback function (if exists)
// // external
// // public
// // internal
// // private
// // internal & private view & pure functions
// // external & public view & pure functions

// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*//////////////////////////////////////////////////////////////
                            IMPORTS
//////////////////////////////////////////////////////////////*/

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/*//////////////////////////////////////////////////////////////
                            CONTRACT
//////////////////////////////////////////////////////////////*/

contract FundMe is Ownable, ReentrancyGuard {
    using PriceConverter for uint256;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error FundMe__NotOwner();
    error FundMe__SpendMoreEth();
    error FundMe__WithdrawFailed();
    error FundMe__NoFundsToWithdraw();
    error FundMe__DeadlineNotYetPleaseWait();
    error FundMe__NotSuccessful();
    error FundMe__GoalReached();
    error FundMe__NotActive();
    error FundMe__InsufficientBalance();
    error FundMe__RefundFailed();

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    enum FundMeState {
        ACTIVE,
        SUCCESS,
        FAILED
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address => uint256) private s_addressToAmountFunded;
    address payable[] private s_funders;

    uint256 private s_totalAmountFunded;
    uint256 private s_totalWithdrawnByOwner;
    uint256 private s_platformFeesCollected;

    AggregatorV3Interface private s_priceFeed;
    FundMeState private s_state;

    uint256 public constant MINIMUM_USD = 5e18;
    uint256 public constant BASIS_POINTS = 10_000;

    uint256 public immutable i_goal;
    uint256 public immutable i_deadline;
    address public immutable i_feeRecipient;
    uint256 public immutable i_platformFeeBps;
    uint256 public immutable i_refundFeeBps;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event Funded(address indexed funder, uint256 amount);
    event OwnerWithdrawn(address indexed owner, uint256 amount);
    event Refunded(address indexed user, uint256 amount, uint256 fee);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the crowdfunding campaign
     * @param priceFeed Chainlink ETH/USD price feed address
     * @param goal Funding goal (in wei)
     * @param feeRecipient Address receiving platform fees
     * @param platformFeeBps Fee taken on successful withdrawals (bps)
     * @param refundFeeBps Fee taken on refunds (bps)
     */
    constructor(
        address priceFeed,
        uint256 goal,
        address feeRecipient,
        uint256 platformFeeBps,
        uint256 refundFeeBps
    ) Ownable(msg.sender) {
        s_priceFeed = AggregatorV3Interface(priceFeed);
        i_deadline = block.timestamp + 60;
        i_goal = goal;

        i_feeRecipient = feeRecipient;
        i_platformFeeBps = platformFeeBps;
        i_refundFeeBps = refundFeeBps;

        s_state = FundMeState.ACTIVE;
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows users to fund the campaign
     * @dev Requires campaign to be ACTIVE and minimum USD contribution met
     */
    function fund() public payable {
        if (s_state != FundMeState.ACTIVE) revert FundMe__NotActive();

        uint256 usdAmount = msg.value.getConversionRate(s_priceFeed);
        if (usdAmount < MINIMUM_USD) revert FundMe__SpendMoreEth();

        if (s_addressToAmountFunded[msg.sender] == 0) {
            s_funders.push(payable(msg.sender));
        }

        s_addressToAmountFunded[msg.sender] += msg.value;
        s_totalAmountFunded += msg.value;

        if (s_totalAmountFunded >= i_goal) {
            s_state = FundMeState.SUCCESS;
        }

        emit Funded(msg.sender, msg.value);
    }

    /**
     * @notice Refunds user contribution if campaign fails
     * @dev Applies refund fee and prevents reentrancy
     */
    function refund() external nonReentrant {
        updateState();

        if (s_state == FundMeState.SUCCESS) revert FundMe__GoalReached();

        if (s_state == FundMeState.ACTIVE && block.timestamp < i_deadline) {
            revert FundMe__DeadlineNotYetPleaseWait();
        }

        uint256 amount = s_addressToAmountFunded[msg.sender];
        if (amount == 0) revert FundMe__NoFundsToWithdraw();

        s_addressToAmountFunded[msg.sender] = 0;

        uint256 fee = (amount * i_refundFeeBps) / BASIS_POINTS;
        uint256 refundAmount = amount - fee;

        s_platformFeesCollected += fee;

        (bool feeSent,) = payable(i_feeRecipient).call{value: fee}("");
        if (!feeSent) revert FundMe__RefundFailed();

        (bool success,) = payable(msg.sender).call{value: refundAmount}("");
        if (!success) revert FundMe__WithdrawFailed();

        emit Refunded(msg.sender, refundAmount, fee);
    }

    /**
     * @notice Allows owner to withdraw funds after success
     * @param amount Amount to withdraw (0 = full balance)
     * @dev Applies platform fee and prevents reentrancy
     */
    function ownerWithdraw(uint256 amount) external onlyOwner nonReentrant {
        if (s_state != FundMeState.SUCCESS) revert FundMe__NotSuccessful();

        uint256 balance = address(this).balance;
        if (balance == 0) revert FundMe__NoFundsToWithdraw();

        uint256 amountToWithdraw = amount == 0 ? balance : amount;
        if (amountToWithdraw > balance) revert FundMe__InsufficientBalance();

        uint256 fee = (amountToWithdraw * i_platformFeeBps) / BASIS_POINTS;
        uint256 payout = amountToWithdraw - fee;

        s_totalWithdrawnByOwner += payout;
        s_platformFeesCollected += fee;

        (bool feeSent,) = payable(i_feeRecipient).call{value: fee}("");
        if (!feeSent) revert FundMe__WithdrawFailed();

        (bool success,) = payable(msg.sender).call{value: payout}("");
        if (!success) revert FundMe__WithdrawFailed();

        emit OwnerWithdrawn(msg.sender, payout);
    }

    /*//////////////////////////////////////////////////////////////
                        FALLBACK / RECEIVE
    //////////////////////////////////////////////////////////////*/

    fallback() external payable {
        fund();
    }

    receive() external payable {
        fund();
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates campaign state based on time and funding
     */
    function updateState() public {
        if (s_state == FundMeState.ACTIVE && block.timestamp >= i_deadline) {
            if (address(this).balance >= i_goal) {
                s_state = FundMeState.SUCCESS;
            } else {
                s_state = FundMeState.FAILED;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns Chainlink price feed version
    function getVersion() public view returns (uint256) {
        return s_priceFeed.version();
    }

    /// @notice Returns price feed address
    function getPriceFeed() public view returns (address) {
        return address(s_priceFeed);
    }

    /// @notice Returns amount funded by a user
    function getAddressToAmountFunded(address user) external view returns (uint256) {
        return s_addressToAmountFunded[user];
    }

    /// @notice Returns funder at index
    function getFunder(uint256 index) external view returns (address) {
        return s_funders[index];
    }

    /// @notice Returns contract owner
    function getOwner() external view returns (address) {
        return owner();
    }

    /// @notice Returns total funded amount
    function getTotalAmountFunded() external view returns (uint256) {
        return s_totalAmountFunded;
    }

    /// @notice Returns current campaign state
    function getState() external view returns (FundMeState) {
        return s_state;
    }

    /// @notice Returns campaign deadline
    function getDeadline() external view returns (uint256) {
        return i_deadline;
    }

    /// @notice Returns total platform fees collected
    function getPlatformFeesCollected() external view returns (uint256) {
        return s_platformFeesCollected;
    }

    /// @notice Returns total withdrawn by owner
    function getTotalWithdrawnByOwner() external view returns (uint256) {
        return s_totalWithdrawnByOwner;
    }
}
