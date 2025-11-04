// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {CredibleTestWithBacktesting} from "credible-std/CredibleTestWithBacktesting.sol";
import {BacktestingTypes} from "credible-std/utils/BacktestingTypes.sol";
import {BatchSwapDeltaAssertion} from "../src/BatchSwapDeltaAssertion.a.sol";

contract BatchSwapBacktest is CredibleTestWithBacktesting {
    address constant BALANCERV2_VAULT_ARB = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    // Block configuration
    uint256 constant END_BLOCK = 396293544;
    uint256 constant BLOCK_RANGE = 5;

    function testBacktest_Balancer_BatchSwapOperations() public {
        BacktestingTypes.BacktestingResults memory results = executeBacktest({
            targetContract: BALANCERV2_VAULT_ARB,
            endBlock: END_BLOCK,
            blockRange: BLOCK_RANGE,
            assertionCreationCode: type(BatchSwapDeltaAssertion).creationCode,
            assertionSelector: BatchSwapDeltaAssertion.assertionBatchSwapNonNegativeDeltas.selector,
            rpcUrl: vm.envString("ARBITRUM_RPC_URL")
        });
    }
}
