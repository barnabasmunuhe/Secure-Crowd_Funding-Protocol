// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract HelperConfig is Script {
    error HelperConfig__UnsupportedNetwork(uint256 chainId);

    uint256 public constant ANVIL_CHAIN_ID = 31337;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant MAINNET_CHAIN_ID = 1;

    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000e8;

    uint256 constant PLATFORM_FEE_BPS = 200; // 2%
    uint256 constant REFUND_FEE_BPS = 100; // 1%

    uint256 public constant GOAL_USD = 10_000e18;
    uint256 public constant MINIMUM_USD = 5e18;

    uint256 public constant CAMPAIGN_DURATION = 7 days;

    address public constant FEE_RECIPIENT = 0x002AC9eA2939aA21E0b6231D74494dc4DA7f9f33;

    struct NetworkConfig {
        address priceFeed;
        uint256 goalUsd;
        uint256 minimumUsd;
        uint256 campaignDuration;
        address feeRecipient;
        uint256 platformFeeBps;
        uint256 refundFeeBps;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == MAINNET_CHAIN_ID) {
            activeNetworkConfig = getMainnetEthConfig();
        } else if (block.chainid == ANVIL_CHAIN_ID) {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__UnsupportedNetwork(block.chainid);
        }
    }

    function getActiveNetworkConfig() external view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            goalUsd: GOAL_USD,
            minimumUsd: MINIMUM_USD,
            campaignDuration: CAMPAIGN_DURATION,
            feeRecipient: FEE_RECIPIENT,
            platformFeeBps: PLATFORM_FEE_BPS,
            refundFeeBps: REFUND_FEE_BPS
        });
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            priceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            goalUsd: GOAL_USD,
            minimumUsd: MINIMUM_USD,
            campaignDuration: CAMPAIGN_DURATION,
            feeRecipient: FEE_RECIPIENT,
            platformFeeBps: PLATFORM_FEE_BPS,
            refundFeeBps: REFUND_FEE_BPS
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.priceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
        vm.stopBroadcast();

        activeNetworkConfig = NetworkConfig({
            priceFeed: address(mockPriceFeed),
            goalUsd: GOAL_USD,
            minimumUsd: MINIMUM_USD,
            campaignDuration: CAMPAIGN_DURATION,
            feeRecipient: FEE_RECIPIENT,
            platformFeeBps: PLATFORM_FEE_BPS,
            refundFeeBps: REFUND_FEE_BPS
        });

        return activeNetworkConfig;
    }
}
