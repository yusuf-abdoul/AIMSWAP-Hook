// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FHE, euint128, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {Common} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import "./AIMStorage.sol";
import "./AIMFHE.sol";

/// @title AIMMatcher - Privacy-preserving intent matching
/// @notice Scans the intent queue using FHE operations to find compatible
///         counterpart intents without revealing amounts or directions.
/// @dev Matching is a two-phase process:
///      Phase 1 (beforeSwap): Scan queue, compute encrypted match conditions,
///                             request async decryption. Store as PENDING_MATCH.
///      Phase 2 (keeper/settleMatchedIntents): Poll decryption results,
///                             confirm match, execute settlement.
library AIMMatcher {
    /// @notice Find a matching intent for a new intent using FHE comparisons
    /// @dev Requests async decryption of match result. Because CoFHE decryption
    ///      is asynchronous, the match may not be immediately confirmable.
    ///      Returns `found=true` only if decryption already resolved (rare in
    ///      production, common in tests). Otherwise the intent is stored and
    ///      the keeper settles later once decryption completes.
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
        uint256 scanLimit = s.scanLimit == 0 ? 16 : uint256(s.scanLimit);
        uint256 toScan = queueLength < scanLimit ? queueLength : scanLimit;

        uint256 currentBlock = block.number;

        // Pre-cache encrypted tolerance constants (avoid re-creating each iteration)
        euint128 tolerance = s.ENC_TOLERANCE;
        euint128 hundred = s.ENC_HUNDRED;

        // Scan intentIds array from front (oldest intents first - FIFO)
        for (uint256 i; i < toScan; ) {
            bytes32 candidateId = pi.intentIds[i];
            AIMStorage.Intent storage candidate = pi.intents[candidateId];

            // Skip non-pending
            if (candidate.status != AIMStorage.IntentStatus.PENDING) {
                unchecked { ++i; }
                continue;
            }

            // Skip expired (using cached block number)
            if (currentBlock > candidate.expireBlock) {
                unchecked { ++i; }
                continue;
            }

            // Check if directions are opposite (encrypted XOR)
            ebool oppositeDirection = FHE.xor(
                newIntent.zeroForOne,
                candidate.zeroForOne
            );
            FHE.allowThis(oppositeDirection);

            // Check if amounts are compatible (within tolerance)
            ebool amountsCompatible = AIMFHE.areAmountsCompatible(
                newIntent.amount,
                candidate.amount,
                tolerance,
                hundred
            );

            // Both conditions must be true
            ebool isMatch = FHE.and(oppositeDirection, amountsCompatible);
            FHE.allowThis(isMatch);

            // Request async decryption of match result
            FHE.decrypt(isMatch);

            // Check if decryption already resolved (fast path for tests / cached results)
            (bool matchResult, bool isDecrypted) = FHE.getDecryptResultSafe(isMatch);

            if (isDecrypted && matchResult) {
                return (candidateId, candidate, true);
            }

            unchecked { ++i; }
        }

        return (bytes32(0), pi.intents[bytes32(0)], false);
    }
}
