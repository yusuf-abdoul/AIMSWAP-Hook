// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    FHE,
    euint128,
    ebool,
    InEuint128
} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/// @title AIMFHE - FHE utility helpers for AIMHook

library AIMFHE {
    event EncryptedIntentStored(
        bytes32 indexed intentId,
        bytes32 ciphertextHash
    );
    /// @notice Initialize encrypted constants
    function initConstants() internal returns (euint128 zero) {
        zero = FHE.asEuint128(0);
        FHE.allowThis(zero);
        return zero;
    }

    /// @notice Check if two encrypted amounts are compatible for matching
    /// @dev Uses FHE.select to avoid revealing exact amounts and prevent underflow
    /// @dev CRITICAL: All FHE operations require access control via FHE.allowThis()
    function areAmountsCompatible(
        euint128 amount1,
        euint128 amount2,
        euint128 tolerance // e.g., 5% = FHE.asEuint128(5)
    ) internal returns (ebool) {
        // Calculate absolute difference safely (no underflow)
        euint128 absDiff = FHE.select(
            FHE.gt(amount1, amount2),
            FHE.sub(amount1, amount2),
            FHE.sub(amount2, amount1)
        );
        FHE.allowThis(absDiff); // Grant contract access to use this value

        // Calculate tolerance threshold: (amount1 * tolerance) / 100
        euint128 product = FHE.mul(amount1, tolerance);
        FHE.allowThis(product); // Grant contract access

        euint128 maxDiff = FHE.div(product, FHE.asEuint128(100));
        FHE.allowThis(maxDiff); // Grant contract access

        // Check if within tolerance
        ebool compatible = FHE.lte(absDiff, maxDiff);
        FHE.allowThis(compatible); // Grant contract access to result

        return compatible;
    }

    /// @notice Calculate matched amount between two intents
    /// @dev Returns minimum of two encrypted amounts
    function calculateMatchedAmount(
        euint128 amount1,
        euint128 amount2
    ) internal returns (euint128) {
        // Compare amounts (encrypted)
        ebool amount1IsLess = FHE.lt(amount1, amount2);
        FHE.allowThis(amount1IsLess); // Grant access to comparison result

        // Return minimum using encrypted selection
        euint128 minAmount = FHE.select(amount1IsLess, amount1, amount2);
        FHE.allowThis(minAmount); // Grant access to result

        return minAmount;
    }
}
