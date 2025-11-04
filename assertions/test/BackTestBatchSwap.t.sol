// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {CredibleTestWithBacktesting} from "credible-std/CredibleTestWithBacktesting.sol";
import {BacktestingTypes} from "credible-std/utils/BacktestingTypes.sol";
import {BatchSwapDeltaAssertion} from "../src/BatchSwapDeltaAssertion.a.sol";
import {console} from "forge-std/console.sol";

contract BatchSwapBacktest is CredibleTestWithBacktesting {
    address constant BALANCERV2_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    // Mainnet Exploit Block (23717632)
    uint256 constant END_BLOCK = 23717632;
    uint256 constant BLOCK_RANGE = 1;

    // Mainnet random batchSwap tx block (23718374)
    // uint256 constant END_BLOCK = 23718374;
    // uint256 constant BLOCK_RANGE = 1;

    // Arbitrum Exploit Block (396293464)
    // uint256 constant END_BLOCK = 396293465;
    // uint256 constant BLOCK_RANGE = 3;

    function testBacktest_Balancer_BatchSwapOperations() public {
        BacktestingTypes.BacktestingResults memory results = executeBacktest({
            targetContract: BALANCERV2_VAULT,
            endBlock: END_BLOCK,
            blockRange: BLOCK_RANGE,
            assertionCreationCode: type(BatchSwapDeltaAssertion).creationCode,
            assertionSelector: BatchSwapDeltaAssertion.assertionBatchSwapNonNegativeDeltas.selector,
            rpcUrl: vm.envString("MAINNET_RPC_URL")
        });
    }
}
