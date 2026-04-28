// SPDX-License-Identifier: MIT

// Fund
// Withdraw

pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol"; //install ChainAccelOrg/foundry-devops
import {FundMe} from "../src/FundMe.sol";

/*//////////////////////////////////////////////////////////////
                      FUND SCRIPT
//////////////////////////////////////////////////////////////*/

contract FundFundMe is Script {
    uint256 constant SEND_VALUE = 15 ether;

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

contract withdrawFundMe is Script {
    function withdrawFunds(address mostRecentlydeployed) public {
        FundMe(payable(mostRecentlydeployed)).ownerWithdraw(0); //pass an amount if needed
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

contract RefundFundMe is Script {
    function refundFundMe(address fundMeAddressRecentlyDeployed) public {
        FundMe(payable(fundMeAddressRecentlyDeployed)).refund();
        console.log("Refund executed");
    }

    function run() external {
        address mostRecent = DevOpsTools.get_most_recent_deployment("FundMe", block.chainid);

        vm.startBroadcast();
        refundFundMe(mostRecent);
        vm.stopBroadcast();
    }
}
