// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol"; //install ChainAccelOrg/foundry-devops
import {FundMe} from "../src/FundMe.sol";

// Interaction script executes real transactions against a deployed contract.

/*//////////////////////////////////////////////////////////////
                      FUND SCRIPT
//////////////////////////////////////////////////////////////*/
// Campaign must be ACTIVE; contribution must meet minimum USD.
contract FundFundMe is Script {
    uint256 public constant SEND_VALUE = 0.01 ether;

    function fundFundMe(address mostRecentlydeployedFundMeAddress) public {
        FundMe(payable(mostRecentlydeployedFundMeAddress)).fund{value: SEND_VALUE}();
        console.log("Funded Fundme with :", SEND_VALUE);
    }

    function run() external {
        address mostRecentlyDeployedContract = DevOpsTools.get_most_recent_deployment("FundMe", block.chainid);

        vm.startBroadcast();
        fundFundMe(mostRecentlyDeployedContract);
        vm.stopBroadcast();
    }
}

/*//////////////////////////////////////////////////////////////
                      WITHDRAW SCRIPT
//////////////////////////////////////////////////////////////*/
// Broadcaster must be owner; campaign must be SUCCESS.
contract withdrawFundMe is Script {
    function withdrawFunds(address mostRecentlydeployedFundMeAddress) public {
        FundMe(payable(mostRecentlydeployedFundMeAddress)).ownerWithdraw(0); //pass an amount if needed
    }

    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("FundMe", block.chainid);
        vm.startBroadcast();
        withdrawFunds(mostRecentlyDeployed);
        vm.stopBroadcast();
    }
}

/*//////////////////////////////////////////////////////////////
                      REFUND SCRIPT
//////////////////////////////////////////////////////////////*/
// Broadcaster must have contributed; campaign must be FAILED.
contract RefundFundMe is Script {
    function refundFundMe(address mostRecentlydeployedFundMeAddress) public {
        FundMe(payable(mostRecentlydeployedFundMeAddress)).refund();
        console.log("Refund executed");
    }

    function run() external {
        address mostRecent = DevOpsTools.get_most_recent_deployment("FundMe", block.chainid);

        vm.startBroadcast();
        refundFundMe(mostRecent);
        vm.stopBroadcast();
    }
}
