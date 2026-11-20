//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {FundMe} from "../src/FundMe.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @title DeployFundMe
/// @notice Deploys FundMe with the configuration for the active network.
contract DeployFundMe is Script {
    function run() external returns (FundMe) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        vm.startBroadcast();
        FundMe fundMe = new FundMe(
            config.priceFeed,
            config.minimumUsd,
            config.goalUsd,
            config.feeRecipient,
            config.platformFeeBps,
            config.refundFeeBps,
            config.campaignDuration
        );
        vm.stopBroadcast();

        return fundMe;
    }
}
