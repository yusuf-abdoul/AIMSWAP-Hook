// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "v4-core/types/BeforeSwapDelta.sol";
import {
    FHE,
    euint128,
    ebool,
    InEuint128
} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {
    ReentrancyGuardTransient
} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import "./AIMStorage.sol";
import "./AIMMatcher.sol";
import "./AIMSettlement.sol";

/// @title AIMHook - Asynchronous Intent Matcher Hook
/// @notice Privacy-preserving CoW protocol for Uniswap v4

contract AIMHook is BaseHook, ReentrancyGuardTransient {
    using AIMStorage for AIMStorage.Storage;
    AIMStorage.Storage internal s;

    // Simple nonce for intent ID uniqueness per owner
    mapping(address => uint256) public ownerNonces;

    // Store PoolKeys for settlement (poolId => PoolKey)
    mapping(bytes32 => PoolKey) public poolKeys;

    event IntentCreated(
        bytes32 indexed poolId,
        bytes32 indexed intentId,
        address owner,
        euint128 amount,
        uint32 expireBlock
    );
    event IntentMatched(
        bytes32 indexed poolId,
        bytes32 indexed intentA,
        bytes32 indexed intentB,
        uint128 amountMatched
    );
    event IntentSettled(
        bytes32 indexed poolId,
        bytes32 indexed intentId,
        uint128 amountSettled
    );
    event IntentExpired(bytes32 indexed poolId, bytes32 indexed intentId);

    /// @notice Constructor
    /// @param _poolManager Uniswap v4 PoolManager address
    /// @param defaultMatchWindowBlocks_ Blocks before intent expires
    /// @param scanLimit_ Max intents to scan per match
    constructor(
        IPoolManager _poolManager,
        uint32 defaultMatchWindowBlocks_,
        uint8 scanLimit_
    ) BaseHook(_poolManager) {

        AIMStorage.Storage storage st = AIMStorage.store();
        st.defaultMatchWindowBlocks = defaultMatchWindowBlocks_;
        st.scanLimit = scanLimit_;

        // Initialize encrypted constants
        st.ENCRYPTED_ZERO = FHE.asEuint128(0);
        FHE.allowThis(st.ENCRYPTED_ZERO);
    }

    /// @notice Define which hooks are used
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true, // ✅ Check for matches
                afterSwap: false, // Could use for cleanup
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true, // ✅ REQUIRED to prevent AMM when matched
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /// @notice Hook called before every swap
    /// @dev This is where intent matching logic runs
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    )
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        bytes32 poolId = PoolId.unwrap(key.toId());

        // Store pool key for future settlement (if not already stored)
        if (address(poolKeys[poolId].hooks) == address(0)) {
            poolKeys[poolId] = key;
        }

        // Decode encrypted intent data from hookData
        (InEuint128 memory encAmount, InEuint128 memory encMinReturn) = abi
            .decode(hookData, (InEuint128, InEuint128));

        // Try to match with existing opposite intent
        (bool matched, bytes32 matchedIntentId) = _handleIntent(
            poolId,
            sender,
            params.zeroForOne,
            encAmount,
            encMinReturn
        );

        if (matched) {
            // Intent matched - PREVENT AMM swap
            // With beforeSwapReturnDelta: true, returning any delta prevents AMM
            // Settlement happens later via settleMatchedIntents() after FHE decryption
            emit IntentMatched(poolId, bytes32(0), matchedIntentId, 0);

            // Return specified delta to prevent AMM interaction
            // Note: Actual amounts unknown until FHE decryption completes
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA, // Hook is handling this swap
                0
            );
        } else {
            // No match - ALLOW AMM swap to proceed
            // Returning ZERO_DELTA with no override lets swap continue to AMM
            // AMM uses pool's sqrtPriceX96 for pricing (no external oracle needed)
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA, // Let AMM handle normally
                0
            );
        }
    }

    /// @notice Handle intent creation and matching
    /// @dev Optimized with unchecked arithmetic and cached storage reads
    function _handleIntent(
        bytes32 poolId,
        address owner,
        bool zeroForOne,
        InEuint128 memory encAmount,
        InEuint128 memory encMinReturn
    ) internal returns (bool matched, bytes32 matchedId) {
        AIMStorage.Storage storage ss = AIMStorage.store();

        // Convert client-encrypted inputs to contract euint128
        euint128 amount = FHE.asEuint128(encAmount);
        euint128 minReturn = FHE.asEuint128(encMinReturn);
        ebool direction = FHE.asEbool(zeroForOne);

        // Create new intent with cached storage values
        uint32 created = uint32(block.number);
        uint32 matchWindow = ss.defaultMatchWindowBlocks; // Cache storage read
        uint32 expire;
        unchecked {
            expire = created + matchWindow; // Safe: block number won't overflow
        }
        uint256 nonce = ownerNonces[owner];
        unchecked {
            ownerNonces[owner] = nonce + 1; // Use unchecked increment
        }

        bytes32 intentId = AIMStorage.makeIntentId(
            poolId,
            owner,
            nonce,
            created
        );

        AIMStorage.Intent memory newIntent = AIMStorage.Intent({
            owner: owner,
            amount: amount,
            minReturn: minReturn,
            zeroForOne: direction,
            createdBlock: created,
            expireBlock: expire,
            status: AIMStorage.IntentStatus.PENDING,
            decryptHandle: 0
        });

        // Grant contract access to encrypted fields
        FHE.allowThis(amount);
        FHE.allowThis(minReturn);
        FHE.allowThis(direction);

        // Try to find matching intent
        (
            bytes32 otherId,
            AIMStorage.Intent storage otherIntent,
            bool found
        ) = AIMMatcher.findMatch(ss, poolId, newIntent);

        if (found) {
            // Match found - settle directly
            _settleMatchedIntents(
                poolId,
                intentId,
                newIntent,
                otherId,
                otherIntent
            );
            return (true, otherId);
        } else {
            // No match - store for future matching
            AIMStorage.PoolIntents storage pi = ss.pools[poolId];
            pi.intents[intentId] = newIntent;
            pi.intentIds.push(intentId); // Add to FIFO queue
            pi.userIntents[owner].push(intentId); // Track per user

            // Grant user access to their encrypted data
            FHE.allowSender(amount);
            FHE.allowSender(minReturn);
            FHE.allowSender(direction);

            // Request async decryption for future settlement
            FHE.decrypt(amount);

            emit IntentCreated(poolId, intentId, owner, amount, expire);
            return (false, bytes32(0));
        }
    }

    /// @notice Settle two matched intents directly (peer-to-peer)
    function _settleMatchedIntents(
        bytes32 poolId,
        bytes32 intentAId,
        AIMStorage.Intent memory intentA,
        bytes32 intentBId,
        AIMStorage.Intent storage intentB
    ) internal nonReentrant {
        AIMStorage.Storage storage ss = AIMStorage.store();

        // Wait for amounts to be decrypted
        (uint128 amountA, bool aDecrypted) = FHE.getDecryptResultSafe(intentA.amount);
        (uint128 amountB, bool bDecrypted) = FHE.getDecryptResultSafe(intentB.amount);

        require(aDecrypted && bDecrypted, "Amounts not decrypted yet");

        // Calculate matched amount (minimum of both)
        uint128 matchedAmount = amountA < amountB ? amountA : amountB;

        // Get direction (need decryption)
        (bool aZeroForOne, bool dirDecrypted) = FHE.getDecryptResultSafe(intentA.zeroForOne);
        require(dirDecrypted, "Direction not decrypted yet");

        // Mark both intents as matched
        ss.pools[poolId].intents[intentAId].status = AIMStorage.IntentStatus.MATCHED;
        intentB.status = AIMStorage.IntentStatus.MATCHED;

        // TODO: Actual token transfers would happen here via PoolManager
        // For now, we just emit the settlement event

        emit IntentSettled(poolId, intentAId, matchedAmount);
        emit IntentSettled(poolId, intentBId, matchedAmount);

        // Update statuses to settled
        ss.pools[poolId].intents[intentAId].status = AIMStorage.IntentStatus.SETTLED;
        intentB.status = AIMStorage.IntentStatus.SETTLED;

        // Handle partial fills
        if (amountA > matchedAmount) {
            // Intent A partially filled - keep remaining in queue
            ss.pools[poolId].intents[intentAId].amount = FHE.asEuint128(amountA - matchedAmount);
            ss.pools[poolId].intents[intentAId].status = AIMStorage.IntentStatus.PENDING; // Back to pending
            FHE.allowThis(ss.pools[poolId].intents[intentAId].amount);
        }

        if (amountB > matchedAmount) {
            // Intent B partially filled
            intentB.amount = FHE.asEuint128(amountB - matchedAmount);
            intentB.status = AIMStorage.IntentStatus.PENDING; // Back to pending
            FHE.allowThis(intentB.amount);
        }
    }

    /// @notice Cleanup expired intents from a pool
    /// @param poolId The pool to cleanup
    /// @param maxToProcess Maximum number of intents to process
    function cleanupExpired(bytes32 poolId, uint256 maxToProcess) external {
        AIMStorage.Storage storage ss = AIMStorage.store();
        AIMStorage.PoolIntents storage pi = ss.pools[poolId];

        uint256 processed = 0;
        uint256 i = 0;

        while (i < pi.intentIds.length && processed < maxToProcess) {
            bytes32 id = pi.intentIds[i];
            AIMStorage.Intent storage intent = pi.intents[id];

            if (intent.status == AIMStorage.IntentStatus.PENDING && block.number > intent.expireBlock) {
                intent.status = AIMStorage.IntentStatus.EXPIRED; // Mark as expired
                emit IntentExpired(poolId, id);

                // Remove from array by swapping with last element
                uint256 lastIndex = pi.intentIds.length - 1;
                if (i != lastIndex) {
                    pi.intentIds[i] = pi.intentIds[lastIndex];
                }
                pi.intentIds.pop();
                processed++;
                // Don't increment i since we swapped a new element into this position
                continue;
            }
            i++;
        }
    }

    /// @notice Get intent details (for UI/debugging)
    /// @param poolId The pool ID
    /// @param intentId The intent ID
    /// @return The intent struct
    function getIntent(bytes32 poolId, bytes32 intentId)
        external
        view
        returns (AIMStorage.Intent memory)
    {
        return AIMStorage.store().pools[poolId].intents[intentId];
    }

    /// @notice Get all intent IDs for a user in a pool
    /// @param poolId The pool ID
    /// @param user The user address
    /// @return Array of intent IDs
    function getUserIntents(bytes32 poolId, address user)
        external
        view
        returns (bytes32[] memory)
    {
        return AIMStorage.store().pools[poolId].userIntents[user];
    }

    /// @notice Get total number of active intents in a pool
    /// @param poolId The pool ID
    /// @return Number of intents
    function getPoolIntentCount(bytes32 poolId)
        external
        view
        returns (uint256)
    {
        return AIMStorage.store().pools[poolId].intentIds.length;
    }

    /// @notice Manually trigger settlement for two matched intents
    /// @param poolId The pool ID
    /// @param intentAId First intent ID
    /// @param intentBId Second intent ID
    /// @dev Can be called by anyone after FHE decryption completes
    /// @dev Useful for keepers/bots to finalize settlements
    function settleMatchedIntents(
        bytes32 poolId,
        bytes32 intentAId,
        bytes32 intentBId
    ) external nonReentrant {
        AIMStorage.Storage storage ss = AIMStorage.store();
        AIMStorage.Intent storage intentA = ss.pools[poolId].intents[intentAId];
        AIMStorage.Intent storage intentB = ss.pools[poolId].intents[intentBId];

        // Verify both intents are in MATCHED status
        require(
            intentA.status == AIMStorage.IntentStatus.MATCHED &&
            intentB.status == AIMStorage.IntentStatus.MATCHED,
            "Intents not matched"
        );

        // Wait for amounts to be decrypted
        (uint128 amountA, bool aDecrypted) = FHE.getDecryptResultSafe(intentA.amount);
        (uint128 amountB, bool bDecrypted) = FHE.getDecryptResultSafe(intentB.amount);

        require(aDecrypted && bDecrypted, "Amounts not decrypted yet");

        // Get direction
        (bool aZeroForOne, bool dirDecrypted) = FHE.getDecryptResultSafe(intentA.zeroForOne);
        require(dirDecrypted, "Direction not decrypted");

        // Calculate matched amount
        uint128 matchedAmount = amountA < amountB ? amountA : amountB;

        // Use AIMSettlement library for actual token transfers
        AIMSettlement.settleTwoIntents(
            poolManager,
            poolId,
            poolKeys[poolId],
            intentAId,
            intentA,
            intentBId,
            intentB
        );

        emit IntentSettled(poolId, intentAId, matchedAmount);
        emit IntentSettled(poolId, intentBId, matchedAmount);
    }
}
