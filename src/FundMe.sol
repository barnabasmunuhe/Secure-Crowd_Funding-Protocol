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
    error FundMe__CampaignEnded();
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
    error FundMe__CampaignAlreadyFinalized();

    // --- constructor validation ---
    error FundMe__InvalidPriceFeed();
    error FundMe__InvalidGoal();
    error FundMe__InvalidDeadline();
    error FundMe__InvalidFeeRecipient();
    error FundMe__InvalidFeeBps();
    error FundMe__InvalidDuration();
    error FundMe__InvalidMinimumUsd();

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

    uint256 private s_totalAmountFunded; // ETH received, in wei
    uint256 private s_totalAmountFundedUsd; // USD value, scaled to 18 decimals
    uint256 private s_totalWithdrawnByOwner;
    uint256 private s_platformFeesCollected;

    AggregatorV3Interface private s_priceFeed;
    FundMeState private s_state;

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MAX_FEE_BPS = 500; // 5% hard cap

    uint256 public immutable i_minimumUsd;
    uint256 public immutable i_goalUsd; // USD, 18 decimals
    uint256 public immutable i_deadline; // Unix timestamp
    address public immutable i_feeRecipient;
    uint256 public immutable i_platformFeeBps;
    uint256 public immutable i_refundFeeBps;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event Funded(address indexed funder, uint256 amount);
    event OwnerWithdrawn(address indexed owner, uint256 amount);
    event Refunded(address indexed user, uint256 amount, uint256 fee);
    event StateChanged(FundMeState newState);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the crowdfunding campaign.
     * @param priceFeed    Chainlink ETH/USD price feed address.
     * @param goalUsd      Funding goal in USD, 18 decimals (e.g. 10_000e18 = $10,000).
     * @param duration Campaign duration in seconds, starting at deployment.
     * @param feeRecipient Address receiving platform fees.
     * @param platformFeeBps Fee on successful withdrawals (bps, max 500).
     * @param refundFeeBps   Fee on refunds (bps, max 500).
     */
    constructor(
        address priceFeed,
        uint256 minimumUsd,
        uint256 goalUsd,
        address feeRecipient,
        uint256 platformFeeBps,
        uint256 refundFeeBps,
        uint256 duration
    ) Ownable(msg.sender) {
        if (priceFeed == address(0) || priceFeed.code.length == 0) {
            revert FundMe__InvalidPriceFeed();
        }

        if (minimumUsd == 0 || minimumUsd > goalUsd) {
            revert FundMe__InvalidMinimumUsd();
        }

        if (AggregatorV3Interface(priceFeed).decimals() != 8) {
            revert FundMe__InvalidPriceFeed();
        }

        if (goalUsd == 0) revert FundMe__InvalidGoal();
        if (duration == 0) revert FundMe__InvalidDuration();
        if (feeRecipient == address(0)) revert FundMe__InvalidFeeRecipient();
        if (platformFeeBps > MAX_FEE_BPS || refundFeeBps > MAX_FEE_BPS) {
            revert FundMe__InvalidFeeBps();
        }

        s_priceFeed = AggregatorV3Interface(priceFeed);
        i_deadline = block.timestamp + duration;
        i_minimumUsd = minimumUsd;
        i_goalUsd = goalUsd;

        i_feeRecipient = feeRecipient;
        i_platformFeeBps = platformFeeBps;
        i_refundFeeBps = refundFeeBps;

        s_state = FundMeState.ACTIVE;
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows users to fund the campaign before its deadline.
     * @dev Contributions must be worth at least MINIMUM_USD.
     */
    function fund() public payable {
        if (s_state != FundMeState.ACTIVE) revert FundMe__NotActive();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= i_deadline) revert FundMe__CampaignEnded();

        uint256 usdAmount = msg.value.getConversionRate(s_priceFeed);
        if (usdAmount < i_minimumUsd) revert FundMe__SpendMoreEth();

        if (s_addressToAmountFunded[msg.sender] == 0) {
            s_funders.push(payable(msg.sender));
        }

        s_addressToAmountFunded[msg.sender] += msg.value;
        s_totalAmountFunded += msg.value;
        s_totalAmountFundedUsd += usdAmount;

        if (s_totalAmountFundedUsd >= i_goalUsd) {
            s_state = FundMeState.SUCCESS;
            emit StateChanged(s_state);
        }

        emit Funded(msg.sender, msg.value);
    }

    /**
     * @notice Refunds user contribution if campaign fails
     * @dev Applies refund fee, prevents reentrancy and follows checks-effects-interactions
     */
    function refund() external nonReentrant {
        updateState();

        if (s_state == FundMeState.SUCCESS) revert FundMe__GoalReached();
        if (s_state != FundMeState.FAILED) revert FundMe__DeadlineNotYetPleaseWait();

        uint256 amount = s_addressToAmountFunded[msg.sender];
        if (amount == 0) revert FundMe__NoFundsToWithdraw();

        s_addressToAmountFunded[msg.sender] = 0;

        uint256 fee = (amount * i_refundFeeBps) / BASIS_POINTS;
        uint256 refundAmount = amount - fee;
        s_platformFeesCollected += fee;

        if (fee > 0) {
            (bool feeSent,) = payable(i_feeRecipient).call{value: fee}("");
            if (!feeSent) revert FundMe__RefundFailed();
        }

        (bool success,) = payable(msg.sender).call{value: refundAmount}("");
        if (!success) revert FundMe__WithdrawFailed();

        emit Refunded(msg.sender, refundAmount, fee);
    }

    /**
     * @notice Allows owner to withdraw funds after compaign success.
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

        if (fee > 0) {
            (bool feeSent,) = payable(i_feeRecipient).call{value: fee}("");
            if (!feeSent) revert FundMe__WithdrawFailed();
        }

        (bool success,) = payable(msg.sender).call{value: payout}("");
        if (!success) revert FundMe__WithdrawFailed();

        emit OwnerWithdrawn(msg.sender, payout);
    }

    /**
     * @notice Finalizes the campaign after its deadline.
     * @dev Anyone may call this; the state can transition only once from ACTIVE.
     */
    function finalizeCampaign() external {
        if (s_state != FundMeState.ACTIVE) revert FundMe__CampaignAlreadyFinalized();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp < i_deadline) revert FundMe__DeadlineNotYetPleaseWait();

        updateState();
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
                        STATE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates campaign state once its deadline has passed.
     * @dev The goal comparison uses cumulative USD value, not the ETH balance.
     */
    function updateState() public {
        // forge-lint: disable-next-line(block-timestamp)
        if (s_state == FundMeState.ACTIVE && block.timestamp >= i_deadline) {
            if (s_totalAmountFundedUsd >= i_goalUsd) {
                s_state = FundMeState.SUCCESS;
            } else {
                s_state = FundMeState.FAILED;
            }
            emit StateChanged(s_state);
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

    /// @notice Returns cumulative USD value funded, scaled to 18 decimals.
    function getTotalAmountFundedUsd() external view returns (uint256) {
        return s_totalAmountFundedUsd;
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
