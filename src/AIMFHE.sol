// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    FHE,
    euint128,
    ebool,
    InEuint128
} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {Common} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import "./AIMStorage.sol";

/// @title AIMFHE - FHE utility helpers for AIMHook
/// @notice Handles encrypted constant initialization, compatibility checks,
///         and async decryption management following CoFHE best practices.
library AIMFHE {
    /// @notice Initialize all encrypted constants used by the protocol.
    /// @dev Must be called once in the constructor. Every encrypted value
    ///      created requires FHE.allowThis() for the contract to use it.
    function initConstants(AIMStorage.Storage storage s) internal {
        s.ENC_ZERO = FHE.asEuint128(0);
        FHE.allowThis(s.ENC_ZERO);

        s.ENC_ONE = FHE.asEuint128(1);
        FHE.allowThis(s.ENC_ONE);

        s.ENC_TOLERANCE = FHE.asEuint128(5); // 5% matching tolerance
        FHE.allowThis(s.ENC_TOLERANCE);

        s.ENC_HUNDRED = FHE.asEuint128(100);
        FHE.allowThis(s.ENC_HUNDRED);
    }

    /// @notice Check if two encrypted amounts are compatible for matching
    /// @dev Uses FHE.select to avoid revealing exact amounts and prevent underflow.
    ///      Every intermediate FHE result gets FHE.allowThis() per CoFHE ACL rules.
    function areAmountsCompatible(
        euint128 amount1,
        euint128 amount2,
        euint128 tolerance,
        euint128 hundred
    ) internal returns (ebool) {
        // Calculate absolute difference safely (no underflow via select)
        ebool a1GtA2 = FHE.gt(amount1, amount2);
        FHE.allowThis(a1GtA2);

        euint128 diffIfGt = FHE.sub(amount1, amount2);
        FHE.allowThis(diffIfGt);

        euint128 diffIfLte = FHE.sub(amount2, amount1);
        FHE.allowThis(diffIfLte);

        euint128 absDiff = FHE.select(a1GtA2, diffIfGt, diffIfLte);
        FHE.allowThis(absDiff);

        // Calculate tolerance threshold: (amount1 * tolerance) / 100
        euint128 product = FHE.mul(amount1, tolerance);
        FHE.allowThis(product);

        euint128 maxDiff = FHE.div(product, hundred);
        FHE.allowThis(maxDiff);

        // Check if within tolerance
        ebool compatible = FHE.lte(absDiff, maxDiff);
        FHE.allowThis(compatible);

        return compatible;
    }

    /// @notice Calculate matched amount between two intents (encrypted min)
    function calculateMatchedAmount(
        euint128 amount1,
        euint128 amount2
    ) internal returns (euint128) {
        ebool amount1IsLess = FHE.lt(amount1, amount2);
        FHE.allowThis(amount1IsLess);

        euint128 minAmount = FHE.select(amount1IsLess, amount1, amount2);
        FHE.allowThis(minAmount);

        return minAmount;
    }

    /// @notice Request async decryption for an intent's amount and track it
    /// @dev Stores the request in decryptRequests mapping for later polling
    function requestDecryption(
        AIMStorage.Storage storage s,
        bytes32 intentId,
        euint128 encValue
    ) internal {
        FHE.decrypt(encValue);
        s.decryptRequests[intentId] = AIMStorage.DecryptRequest({
            encValue: encValue,
            requestBlock: uint32(block.number),
            resolved: false,
            plainValue: 0
        });
    }

    /// @notice Poll for a decryption result, updating cache if resolved
    /// @return value The decrypted plaintext value
    /// @return ready Whether decryption has completed
    function pollDecryption(
        AIMStorage.Storage storage s,
        bytes32 intentId
    ) internal returns (uint128 value, bool ready) {
        AIMStorage.DecryptRequest storage req = s.decryptRequests[intentId];

        // Already resolved - return cached value
        if (req.resolved) {
            return (req.plainValue, true);
        }

        // Check if CoFHE coprocessor has resolved
        if (Common.isInitialized(req.encValue)) {
            (uint128 result, bool isReady) = FHE.getDecryptResultSafe(req.encValue);
            if (isReady) {
                req.resolved = true;
                req.plainValue = result;
                return (result, true);
            }
        }

        return (0, false);
    }
}
