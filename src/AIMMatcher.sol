// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FHE, euint128, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import "./AIMStorage.sol";
import "./AIMFHE.sol";

/// @title AIMMatcher - Privacy-preserving intent matching
library AIMMatcher {
    using AIMStorage for AIMStorage.Storage;

    /// @notice Find matching intent for new intent
    /// @dev Uses FHE operations to compare without revealing amounts
    /// @dev Optimized for gas efficiency with unchecked arithmetic and cached values
    function findMatch(
        AIMStorage.Storage storage s,
        bytes32 poolId,
        AIMStorage.Intent memory newIntent
    )
        internal
        returns (
            bytes32 matchedId,
            AIMStorage.Intent storage matchedIntent,
            bool found
        )
    {
        AIMStorage.PoolIntents storage pi = s.pools[poolId];

        uint256 queueLength = pi.intentIds.length;
        if (queueLength == 0) {
            return (bytes32(0), pi.intents[bytes32(0)], false);
        }

        // Cache scan limit to avoid repeated SLOAD
        uint256 scanLimit = s.scanLimit == 0 ? 16 : s.scanLimit;
        uint256 toScan = queueLength < scanLimit ? queueLength : scanLimit;

        // Cache current block number to save gas
        uint256 currentBlock = block.number;

        // Scan intentIds array from front (oldest intents first - FIFO)
        for (uint256 i; i < toScan; ) {
            bytes32 candidateId = pi.intentIds[i];
            AIMStorage.Intent storage candidate = pi.intents[candidateId];

            // Skip if not pending
            if (candidate.status != AIMStorage.IntentStatus.PENDING) {
                unchecked { ++i; }
                continue;
            }

            // Skip if expired (using cached block number)
            if (currentBlock > candidate.expireBlock) {
                unchecked { ++i; }
                continue;
            }

            // Check if directions are opposite (encrypted)
            ebool oppositeDirection = FHE.xor(
                newIntent.zeroForOne,
                candidate.zeroForOne
            );
            FHE.allowThis(oppositeDirection); // CRITICAL: Grant access

            // Check if amounts are compatible (within tolerance)
            // Note: tolerance constant should be passed in or cached for gas optimization
            ebool amountsCompatible = AIMFHE.areAmountsCompatible(
                newIntent.amount,
                candidate.amount,
                FHE.asEuint128(5) // 5% tolerance
            );
            // Note: areAmountsCompatible already calls FHE.allowThis internally

            // Both conditions must be true
            ebool isMatch = FHE.and(oppositeDirection, amountsCompatible);
            FHE.allowThis(isMatch); // CRITICAL: Grant access to match result

            // Request async decryption for match result
            FHE.decrypt(isMatch);

            // If decrypted result is available, check it
            (bool matchResult, bool isDecrypted) = FHE.getDecryptResultSafe(
                isMatch
            );

            if (isDecrypted && matchResult) {
                // Match found!
                return (candidateId, candidate, true);
            }

            unchecked { ++i; }
        }

        return (bytes32(0), pi.intents[bytes32(0)], false);
    }
}
