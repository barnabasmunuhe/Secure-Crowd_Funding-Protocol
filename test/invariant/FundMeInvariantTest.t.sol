//SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

import {FundMe} from "../../src/FundMe.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Handler} from "./Handler.t.sol";
import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract FundMeInvariantTest is StdInvariant, Test {
    FundMe public fundMe;
    Handler public handler;

    address FEE_RECIPIENT = makeAddr("feeRecipient");

    uint256 constant GOAL = 5 ether;
    uint256 constant PLATFORM_FEE_BPS = 200;
    uint256 constant REFUND_FEE_BPS = 100;

    uint8 constant DECIMALS = 8;
    int256 constant ETHPRICE = 2000e8;

    function setUp() external {
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, ETHPRICE);
        fundMe = new FundMe(address(mockPriceFeed), GOAL, FEE_RECIPIENT, PLATFORM_FEE_BPS, REFUND_FEE_BPS);
        handler = new Handler(fundMe);
        targetContract(address(handler));
    }

    function invariant_balanceMatchesHandler() public view {
        assertEq(address(fundMe).balance, handler.totalFunded());
    }
}
