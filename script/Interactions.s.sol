// // SPDX-License-Identifier: MIT

// // Fund
// // Withdraw

// pragma solidity ^0.8.28;

// import {Script, console} from "forge-std/Script.sol";
// import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol"; //install ChainAccelOrg/foundry-devops
// import {FundMe} from "../src/FundMe.sol";

// contract FundFundMe is Script {
//     uint256 constant SEND_VALUE = 0.01 ether;

//     function fundFundMe(address mostRecentlydeployed) public {
//         FundMe(payable(mostRecentlydeployed)).fund{value: SEND_VALUE}();
//         console.log("Funded Fundme with %s", SEND_VALUE);
//     }

//     function run() external {
//         address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("FundMe", block.chainid);
//         vm.startBroadcast();
//         fundFundMe(mostRecentlyDeployed);
//         vm.stopBroadcast();
//     }
// }

// contract withdrawFundMe is Script {
//     function withdrawfundMe(address mostRecentlydeployed) public {
//         vm.startBroadcast();
//         FundMe(payable(mostRecentlydeployed)).ownerWithdraw();
//         vm.stopBroadcast();
//     }

//     function run() external view {
//         address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("FundMe", block.chainid);

//         withdrawFundMe(mostRecentlyDeployed);
//     }
// }
