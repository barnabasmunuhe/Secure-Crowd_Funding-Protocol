//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {FundMe} from "../src/FundMe.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/**
 * @author  . Barney
 * @title   . Deploys the FundMe contract and its dependencies.
 * @dev     . This script uses Foundry's Script functionality to deploy the FundMe contract. It first checks the current network and deploys a MockV3Aggregator if necessary (for local testing). It then deploys the FundMe contract with the appropriate price feed address based on the network. The script also includes configuration for different networks, allowing for seamless deployment across various environments.
 * @notice  . To run this script, use the command: `forge script script/DeployFundMe.s.sol --broadcast`. Make sure to set up your environment variables for the private key and RPC URL if deploying to a live network.
 */

contract DeployFundMe is Script {
    function run() external returns (FundMe) {
        // Load config
        HelperConfig helperConfig = new HelperConfig(); //creatig a new instance of HelperConfig to access the activeNetworkConfig
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig(); //getting the active network configuration
        // address ethUsdPriceFeed = helperConfig.activeNetworkConfig(); NOW HelpperConfig returns a struct with all params not an address

        // Broadcasting the deployment transaction
        vm.startBroadcast();
        FundMe fundMe =
            new FundMe(config.priceFeed, config.goal, config.feeRecipient, config.platformFeeBps, config.refundFeeBps);
        vm.stopBroadcast();

        return fundMe;
    }
}
