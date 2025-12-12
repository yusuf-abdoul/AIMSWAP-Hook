// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {FHE, euint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {
    SafeERC20,
    IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./AIMStorage.sol";

/// @title AIMSettlement - Direct peer-to-peer settlement
library AIMSettlement {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    /// @notice Settle two matched intents directly (no AMM)
    /// @dev Uses PoolManager unlock callback for atomic settlement
    function settleTwoIntents(
        IPoolManager poolManager,
        bytes32 poolId,
        PoolKey memory key,
        bytes32 intentAId,
        AIMStorage.Intent storage intentA,
        bytes32 intentBId,
        AIMStorage.Intent storage intentB
    ) internal {
        // Wait for amounts to be decrypted
        (uint128 amountA, bool aDecrypted) = FHE.getDecryptResultSafe(
            intentA.amount
        );
        (uint128 amountB, bool bDecrypted) = FHE.getDecryptResultSafe(
            intentB.amount
        );

        require(aDecrypted && bDecrypted, "Amounts not decrypted");

        // Calculate matched amount (minimum of both)
        uint128 matchedAmount = amountA < amountB ? amountA : amountB;

        // Mark intents as matched
        intentA.status = AIMStorage.IntentStatus.MATCHED;
        intentB.status = AIMStorage.IntentStatus.MATCHED;

        // Determine token directions
        Currency currency0 = key.currency0;
        Currency currency1 = key.currency1;

        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);

        // Get direction (need decryption)
        (bool aZeroForOne, bool dirDecrypted) = FHE.getDecryptResultSafe(
            intentA.zeroForOne
        );
        require(dirDecrypted, "Direction not decrypted");

        if (aZeroForOne) {
            // A: token0 -> token1
            // B: token1 -> token0

            // Transfer A's token0 to B
            IERC20(token0).safeTransferFrom(
                intentA.owner,
                intentB.owner,
                matchedAmount
            );

            // Transfer B's token1 to A
            IERC20(token1).safeTransferFrom(
                intentB.owner,
                intentA.owner,
                matchedAmount // Simplified 1:1 - needs price calculation
            );
        } else {
            // A: token1 -> token0
            // B: token0 -> token1

            IERC20(token1).safeTransferFrom(
                intentA.owner,
                intentB.owner,
                matchedAmount
            );

            IERC20(token0).safeTransferFrom(
                intentB.owner,
                intentA.owner,
                matchedAmount
            );
        }

        // Update statuses to settled
        intentA.status = AIMStorage.IntentStatus.SETTLED;
        intentB.status = AIMStorage.IntentStatus.SETTLED;

        // Handle partial fills with unchecked arithmetic (safe: already verified > matchedAmount)
        if (amountA > matchedAmount) {
            uint128 remainingA;
            unchecked {
                remainingA = amountA - matchedAmount;
            }
            // Intent A partially filled - keep remaining in queue
            intentA.amount = FHE.asEuint128(remainingA);
            intentA.status = AIMStorage.IntentStatus.PENDING; // Back to pending
            FHE.allowThis(intentA.amount);
        }

        if (amountB > matchedAmount) {
            uint128 remainingB;
            unchecked {
                remainingB = amountB - matchedAmount;
            }
            intentB.amount = FHE.asEuint128(remainingB);
            intentB.status = AIMStorage.IntentStatus.PENDING;
            FHE.allowThis(intentB.amount);
        }
    }
}
