// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {FHE, euint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {
    SafeERC20,
    IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./AIMStorage.sol";
import "./AIMFHE.sol";

/// @title AIMSettlement - Direct peer-to-peer settlement via PoolManager
/// @notice Handles settlement of matched intents using the Uniswap v4
///         PoolManager's unlock/take/settle callback pattern.
/// @dev Settlement flow:
///      1. Keeper calls settleMatchedIntents() on AIMHook
///      2. AIMHook calls poolManager.unlock() with settlement data
///      3. PoolManager calls back to unlockCallback()
///      4. Inside callback: take() tokens from pool, transfer to recipients, settle() debts
library AIMSettlement {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    /// @notice Settle two matched intents via direct P2P transfer
    /// @dev Called after FHE decryption of amounts and direction has completed.
    ///      Uses SafeERC20 for token transfers between intent owners.
    ///      Handles partial fills by creating remainder intents.
    function settleTwoIntents(
        AIMStorage.Storage storage s,
        bytes32 poolId,
        PoolKey memory key,
        bytes32 intentAId,
        AIMStorage.Intent storage intentA,
        bytes32 intentBId,
        AIMStorage.Intent storage intentB
    ) internal {
        // Poll decryption results for both intents
        (uint128 amountA, bool aReady) = AIMFHE.pollDecryption(s, intentAId);
        (uint128 amountB, bool bReady) = AIMFHE.pollDecryption(s, intentBId);

        require(aReady && bReady, "AIM: amounts not decrypted");

        // Get direction decryption
        (bool aZeroForOne, bool dirReady) = FHE.getDecryptResultSafe(intentA.zeroForOne);
        require(dirReady, "AIM: direction not decrypted");

        // Calculate matched amount (minimum of both)
        uint128 matchedAmount = amountA < amountB ? amountA : amountB;
        require(matchedAmount > 0, "AIM: zero match amount");

        // Resolve token addresses from pool key
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        // Execute P2P token transfers based on direction
        // Intent A sells one token, Intent B sells the opposite
        if (aZeroForOne) {
            // A: token0 -> token1 (A gives token0, wants token1)
            // B: token1 -> token0 (B gives token1, wants token0)
            _safeTransfer(token0, intentA.owner, intentB.owner, matchedAmount);
            _safeTransfer(token1, intentB.owner, intentA.owner, matchedAmount);
        } else {
            // A: token1 -> token0 (A gives token1, wants token0)
            // B: token0 -> token1 (B gives token0, wants token1)
            _safeTransfer(token1, intentA.owner, intentB.owner, matchedAmount);
            _safeTransfer(token0, intentB.owner, intentA.owner, matchedAmount);
        }

        // Update statuses to settled
        intentA.status = AIMStorage.IntentStatus.SETTLED;
        intentB.status = AIMStorage.IntentStatus.SETTLED;

        // Handle partial fills - remainder goes back to PENDING
        if (amountA > matchedAmount) {
            uint128 remainingA;
            unchecked { remainingA = amountA - matchedAmount; }
            intentA.amount = FHE.asEuint128(remainingA);
            FHE.allowThis(intentA.amount);
            intentA.status = AIMStorage.IntentStatus.PENDING;
            // Re-request decryption for the new remainder
            AIMFHE.requestDecryption(s, intentAId, intentA.amount);
        }

        if (amountB > matchedAmount) {
            uint128 remainingB;
            unchecked { remainingB = amountB - matchedAmount; }
            intentB.amount = FHE.asEuint128(remainingB);
            FHE.allowThis(intentB.amount);
            intentB.status = AIMStorage.IntentStatus.PENDING;
            AIMFHE.requestDecryption(s, intentBId, intentB.amount);
        }
    }

    /// @dev Safe transfer helper using SafeERC20
    function _safeTransfer(
        address token,
        address from,
        address to,
        uint256 amount
    ) private {
        if (token == address(0)) {
            // Native ETH transfer - not typical in Uniswap v4 but handle it
            (bool success, ) = to.call{value: amount}("");
            require(success, "AIM: ETH transfer failed");
        } else {
            IERC20(token).safeTransferFrom(from, to, amount);
        }
    }
}
