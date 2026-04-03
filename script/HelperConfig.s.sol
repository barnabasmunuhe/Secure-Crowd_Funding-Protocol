// // SPDX-License-Identifier: MIT

// //1. Deploy mock when we are on local anvil chain
// //2. Keep track of contract address across different chains
// //Sepolia ETH/USD
// //Mainnet ETH/USD

// pragma solidity ^0.8.28;

// import {Script} from "forge-std/Script.sol";
// import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

// contract HelperConfig is Script {
//     //If we are on local anvil chain, deploy mocks
//     //Otherwise, grab the existing address from the live network
//     NetworkConfig public activeNetworkConfig;

//     uint8 public constant DECIMALS = 8;
//     int256 public constant INITIAL_PRICE = 2000e8;

//     struct NetworkConfig {
//         address priceFeed; //ETH/USD price feed address
//     }

//     constructor() {
//         if (block.chainid == 11155111) {
//             activeNetworkConfig = getSepoliaEthConfig();
//         } else if (block.chainid == 1) {
//             activeNetworkConfig = getMainnetEthConfig();
//         } else {
//             activeNetworkConfig = getOrCreateAnvilEthConfig();
//         }
//     } //this sets activeNetworkConfig automatically based on the environment

//     function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
//         //price feed Address
//         NetworkConfig memory sepoliaConfig = NetworkConfig({priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306});
//         return sepoliaConfig;
//     }

//     function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
//         //price feed Address
//         NetworkConfig memory ethConfig = NetworkConfig({priceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419});
//         return ethConfig;
//     }

//     function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
//         //price feed Address
//         if (activeNetworkConfig.priceFeed != address(0)) {
//             return activeNetworkConfig;
//         }

//         //1. Deploy the mocks
//         //2. Return the mock address
//         vm.startBroadcast();
//         MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
//         vm.stopBroadcast();
//         NetworkConfig memory anvilConfig = NetworkConfig({priceFeed: address(mockPriceFeed)});
//         return anvilConfig;
//     }
// }
