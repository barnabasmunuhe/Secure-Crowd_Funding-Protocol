// // SPDX-License-Identifier: MIT

// //1. Deploy mock when we are on local anvil chain
// //2. Keep track of contract address across different chains
// //Sepolia ETH/USD
// //Mainnet ETH/USD

// pragma solidity ^0.8.28;

// import {Script} from "forge-std/Script.sol";
// import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

// contract HelperConfig is Script {
//     uint8 public constant DECIMALS = 8;
//     int256 public constant INITIAL_PRICE = 2000e8;
//     uint256 constant PLATFORM_FEE_BPS = 200; // 2%
//     uint256 constant REFUND_FEE_BPS = 100; // 1%
//     uint256 public constant CAMPAIGN_DURATION = 7 days;

//     struct NetworkConfig {
//         address priceFeed;
//         uint256 goal; // USD, 18 decimals
//         uint256 campaignDuration; // seconds
//         address feeRecipient;
//         uint256 platformFeeBps;
//         uint256 refundFeeBps;
//     }

//     NetworkConfig public activeNetworkConfig;

//     constructor() {
//         if (block.chainid == 11155111) {
//             activeNetworkConfig = getSepoliaEthConfig();
//         } else if (block.chainid == 1) {
//             activeNetworkConfig = getMainnetEthConfig();
//         } else {
//             activeNetworkConfig = getOrCreateAnvilEthConfig();
//         }
//     }

//     function getActiveNetworkConfig() external view returns (NetworkConfig memory) {
//         return activeNetworkConfig;
//     }

//     function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
//         return NetworkConfig({
//             priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
//             goal: 5e18,
//             campaignDuration: CAMPAIGN_DURATION,
//             feeRecipient: 0x002AC9eA2939aA21E0b6231D74494dc4DA7f9f33,
//             platformFeeBps: PLATFORM_FEE_BPS,
//             refundFeeBps: REFUND_FEE_BPS
//         });
//     }

//     function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
//         return NetworkConfig({
//             priceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
//             goal: 20e18,
//             campaignDuration: CAMPAIGN_DURATION,
//             feeRecipient: 0x002AC9eA2939aA21E0b6231D74494dc4DA7f9f33,
//             platformFeeBps: PLATFORM_FEE_BPS,
//             refundFeeBps: REFUND_FEE_BPS
//         });
//     }

//     function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
//         if (activeNetworkConfig.priceFeed != address(0)) {
//             return activeNetworkConfig;
//         }

//         vm.startBroadcast();
//         MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
//         vm.stopBroadcast();

//         return NetworkConfig({
//             priceFeed: address(mockPriceFeed),
//             goal: 20e18,
//             campaignDuration: CAMPAIGN_DURATION,
//             feeRecipient: 0x002AC9eA2939aA21E0b6231D74494dc4DA7f9f33,
//             platformFeeBps: PLATFORM_FEE_BPS,
//             refundFeeBps: REFUND_FEE_BPS
//         });
//     }
// }
