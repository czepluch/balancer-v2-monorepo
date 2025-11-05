// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import "@balancer-labs/v2-interfaces/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/vault/IAsset.sol";

// Interface for pools that implement getRate()
interface IRateProvider {
    function getRate() external view returns (uint256);
}

/**
 * @title BatchSwapDeltaAssertion
 * @notice Detects extreme rate manipulation in Balancer V2 stable pools during batch swaps.
 *
 * @dev This assertion protects against exploits that manipulate pool rates through
 *      accumulated rounding errors in the stable pool invariant calculation.
 *
 *      The exploit pattern:
 *      - Long alternating batchSwap sequences manipulate balances near rounding boundaries
 *      - Accumulated down-rounding biases the invariant D downward
 *      - Lower D reduces BPT price (rate = D / totalSupply)
 *      - Attacker extracts value via internal balance withdrawal
 *
 * Invariant: Pool rates should not change drastically within a single batchSwap call.
 * - Flag if any pool's rate changes by more than 3x (or less than 0.33x)
 */
contract BatchSwapDeltaAssertion is Assertion {
    // Maximum allowed rate change: 3x multiplier in 18 decimals
    uint256 constant MAX_RATE_CHANGE_MULTIPLIER = 3e18; // 3.0x
    uint256 constant MIN_RATE_CHANGE_MULTIPLIER = 33e16; // 0.33x (inverse of 3)
    uint256 constant ONE = 1e18;

    /**
     * @notice Register trigger on batchSwap function calls
     * @dev This assertion runs after every batchSwap call to the Vault
     */
    function triggers() external view override {
        registerCallTrigger(this.assertionBatchSwapRateManipulation.selector, IVault.batchSwap.selector);
    }

    /**
     * @notice Validates that pool rates don't change drastically during a batch swap
     * @dev Checks getRate() before and after the swap for all affected pools
     */
    function assertionBatchSwapRateManipulation() external {
        address vault = ph.getAssertionAdopter();

        // Get all batchSwap calls in this transaction
        PhEvm.CallInputs[] memory batchSwapCalls = ph.getAllCallInputs(vault, IVault.batchSwap.selector);

        // Check each batch swap call
        for (uint256 i = 0; i < batchSwapCalls.length; i++) {
            PhEvm.CallInputs memory callInput = batchSwapCalls[i];

            // Decode the batchSwap call parameters
            (, // SwapKind kind
                IVault.BatchSwapStep[] memory swaps,, // IAsset[] memory assets
                , // FundManagement memory funds
                , // int256[] memory limits
                // uint256 deadline
            ) = abi.decode(
                callInput.input,
                (IVault.SwapKind, IVault.BatchSwapStep[], IAsset[], IVault.FundManagement, int256[], uint256)
            );

            // Extract unique pool IDs from the swap steps
            bytes32[] memory uniquePoolIds = _getUniquePoolIds(swaps);

            // Check rate changes for each affected pool
            for (uint256 j = 0; j < uniquePoolIds.length; j++) {
                bytes32 poolId = uniquePoolIds[j];

                // Get pool address from Vault
                (address poolAddress,) = IVault(vault).getPool(poolId);

                // Fork to pre-call state and read rate
                ph.forkPreCall(callInput.id);
                uint256 preRate = _getPoolRate(poolAddress);

                // Fork to post-call state and read rate
                ph.forkPostCall(callInput.id);
                uint256 postRate = _getPoolRate(poolAddress);

                // Check if rate changed drastically
                // Avoid division by zero
                if (preRate == 0) continue;

                // Calculate rate change multiplier (postRate / preRate)
                uint256 rateChangeMultiplier = (postRate * ONE) / preRate;

                // Flag if rate increased by >3x or decreased to <0.33x
                require(
                    rateChangeMultiplier <= MAX_RATE_CHANGE_MULTIPLIER
                        && rateChangeMultiplier >= MIN_RATE_CHANGE_MULTIPLIER,
                    "BatchSwap: Extreme pool rate manipulation detected"
                );
            }
        }
    }

    /**
     * @dev Extracts unique pool IDs from batch swap steps
     */
    function _getUniquePoolIds(IVault.BatchSwapStep[] memory swaps) internal pure returns (bytes32[] memory) {
        // First pass: count unique pool IDs
        bytes32[] memory allPoolIds = new bytes32[](swaps.length);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < swaps.length; i++) {
            bytes32 poolId = swaps[i].poolId;
            bool isDuplicate = false;

            // Check if we've seen this poolId before
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (allPoolIds[j] == poolId) {
                    isDuplicate = true;
                    break;
                }
            }

            if (!isDuplicate) {
                allPoolIds[uniqueCount] = poolId;
                uniqueCount++;
            }
        }

        // Second pass: create array with only unique IDs
        bytes32[] memory uniquePoolIds = new bytes32[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            uniquePoolIds[i] = allPoolIds[i];
        }

        return uniquePoolIds;
    }

    /**
     * @dev Safely gets the rate from a pool, returns 0 if pool doesn't support getRate()
     */
    function _getPoolRate(address pool) internal view returns (uint256) {
        // Try to call getRate() on the pool
        try IRateProvider(pool).getRate() returns (uint256 rate) {
            return rate;
        } catch {
            // Pool doesn't implement getRate() or call failed
            return 0;
        }
    }
}
