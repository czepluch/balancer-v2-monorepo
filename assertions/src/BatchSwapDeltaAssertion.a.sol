// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import "@balancer-labs/v2-interfaces/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/vault/IAsset.sol";
import "@balancer-labs/v2-interfaces/solidity-utils/openzeppelin/IERC20.sol";

/**
 * @title BatchSwapDeltaAssertion
 * @notice Detects the critical invariant violation where all deltas are negative
 *         during a batch swap, indicating value is being drained from the Vault.
 *
 * @dev This assertion protects against the exploit where both assets in a swap
 *      have negative deltas, meaning the Vault sends both assets without receiving
 *      anything in return. This was the vector for a critical Balancer vulnerability.
 *
 * Invariant: In any valid batchSwap:
 * - At least one asset must have a positive or zero delta (Vault receives or no change)
 * - It's invalid for ALL participating assets to have negative deltas (Vault only sends)
 */
contract BatchSwapDeltaAssertion is Assertion {
    /**
     * @notice Register trigger on batchSwap function calls
     * @dev This assertion runs after every batchSwap call to the Vault
     */
    function triggers() external view override {
        registerCallTrigger(this.assertionBatchSwapNonNegativeDeltas.selector, IVault.batchSwap.selector);
    }

    /**
     * @notice Validates that not all deltas are negative in a batch swap
     * @dev Checks that at least one asset flows INTO the Vault (positive delta)
     *      or has no change (zero delta). Prevents value drainage attacks.
     */
    function assertionBatchSwapNonNegativeDeltas() external {
        address vault = ph.getAssertionAdopter();

        // Get all batchSwap calls in this transaction
        PhEvm.CallInputs[] memory batchSwapCalls = ph.getAllCallInputs(vault, IVault.batchSwap.selector);

        // Check each batch swap call
        for (uint256 i = 0; i < batchSwapCalls.length; i++) {
            _checkBatchSwapDeltas(vault, batchSwapCalls[i]);
        }
    }

    /**
     * @notice Checks a single batchSwap call for the delta invariant violation
     * @dev Measures balance changes for each asset to determine deltas
     * @param vault The Vault contract being monitored
     * @param callInput The specific batchSwap call to analyze
     */
    function _checkBatchSwapDeltas(address vault, PhEvm.CallInputs memory callInput) private {
        // Decode the batchSwap call parameters
        // batchSwap(SwapKind kind, BatchSwapStep[] swaps, IAsset[] assets, FundManagement funds, int256[] limits, uint256 deadline)
        (
            , // SwapKind kind - not needed
            , // BatchSwapStep[] memory swaps - not needed
            IAsset[] memory assets,
            , // FundManagement memory funds - not needed
            , // int256[] memory limits - not needed
                // uint256 deadline - not needed
        ) = abi.decode(
            callInput.input,
            (IVault.SwapKind, IVault.BatchSwapStep[], IAsset[], IVault.FundManagement, int256[], uint256)
        );

        // Track deltas: count how many are negative vs non-negative
        uint256 negativeDeltas = 0;
        uint256 nonNegativeDeltas = 0;
        uint256 totalTrackedAssets = 0;

        // Check balance changes for each asset
        for (uint256 j = 0; j < assets.length; j++) {
            address assetAddress = address(assets[j]);

            // Skip ETH (address 0) - handle it separately if needed
            if (assetAddress == address(0)) continue;

            // Get Vault balance before this specific call
            ph.forkPreCall(callInput.id);
            uint256 preBalance = IERC20(assetAddress).balanceOf(vault);

            // Get Vault balance after this specific call
            ph.forkPostCall(callInput.id);
            uint256 postBalance = IERC20(assetAddress).balanceOf(vault);

            // Calculate delta (positive = Vault received, negative = Vault sent)
            int256 delta = int256(postBalance) - int256(preBalance);

            totalTrackedAssets++;

            if (delta < 0) {
                negativeDeltas++;
            } else {
                // delta >= 0 (Vault received tokens or no change)
                nonNegativeDeltas++;
            }
        }

        // CRITICAL INVARIANT: Cannot have ALL deltas be negative
        // At least one asset must flow INTO the Vault (positive) or stay unchanged (zero)
        require(
            totalTrackedAssets == 0 || nonNegativeDeltas > 0, "BatchSwap: All deltas negative - value drainage detected"
        );

        // Additional safety check for the common two-asset swap case
        // This makes the error more explicit for the most common scenario
        if (totalTrackedAssets == 2 && negativeDeltas == 2) {
            revert("BatchSwap: Both deltas negative in two-asset swap - exploit detected");
        }
    }
}
