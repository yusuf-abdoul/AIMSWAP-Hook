// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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
import "./AIMFHE.sol";
import "./FHEClientHelper.sol";

/// @title AIMHook - Asynchronous Intent Matcher Hook
/// @notice Privacy-preserving CoW protocol for Uniswap v4 using Fhenix CoFHE.
/// @dev Encrypts swap amounts and directions end-to-end. Matching happens on
///      encrypted values via the CoFHE coprocessor. Settlement occurs after
///      async decryption completes, triggered by keepers.
///
///      Supported chains: Arbitrum Sepolia (421614), Ethereum Sepolia (11155111)
///      FHE stack: Fhenix cofhe-contracts with cofhejs frontend SDK
contract AIMHook is BaseHook, ReentrancyGuardTransient {
    using AIMStorage for AIMStorage.Storage;

    // Simple nonce for intent ID uniqueness per owner
    mapping(address => uint256) public ownerNonces;

    // Store PoolKeys for settlement (poolId => PoolKey)
    mapping(bytes32 => PoolKey) public poolKeys;

    // --- Events ---
    event IntentCreated(
        bytes32 indexed poolId,
        bytes32 indexed intentId,
        address indexed owner,
        uint32 expireBlock
    );
    event IntentMatched(
        bytes32 indexed poolId,
        bytes32 indexed intentA,
        bytes32 indexed intentB
    );
    event IntentSettled(
        bytes32 indexed poolId,
        bytes32 indexed intentId,
        uint128 amountSettled
    );
    event IntentExpired(bytes32 indexed poolId, bytes32 indexed intentId);

    // --- Errors ---
    error InvalidEncryptedInput();
    error IntentsNotMatched();
    error DecryptionNotReady();

    /// @notice Constructor
    /// @param _poolManager Uniswap v4 PoolManager address
    /// @param defaultMatchWindowBlocks_ Blocks before intent expires
    /// @param scanLimit_ Max intents to scan per match attempt
    constructor(
        IPoolManager _poolManager,
        uint32 defaultMatchWindowBlocks_,
        uint8 scanLimit_
    ) BaseHook(_poolManager) {
        AIMStorage.Storage storage s = AIMStorage.store();
        s.defaultMatchWindowBlocks = defaultMatchWindowBlocks_;
        s.scanLimit = scanLimit_;

        // Initialize all encrypted constants with proper FHE.allowThis() permissions
        AIMFHE.initConstants(s);
    }

    // ─────────────────────────────────────────────
    // Hook Permissions
    // ─────────────────────────────────────────────

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
                beforeSwap: true,                    // Intercept swaps for intent matching
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,          // Can prevent AMM when matched
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // ─────────────────────────────────────────────
    // Core Hook Logic
    // ─────────────────────────────────────────────

    /// @notice Hook called before every swap - entry point for intent matching
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

        // Decode and validate encrypted intent data from hookData
        (InEuint128 memory encAmount, InEuint128 memory encMinReturn) = abi
            .decode(hookData, (InEuint128, InEuint128));

        // Validate encrypted inputs before processing
        if (!FHEClientHelper.validateInEuint128(encAmount) ||
            !FHEClientHelper.validateInEuint128(encMinReturn)) {
            revert InvalidEncryptedInput();
        }

        // Try to match with existing opposite intent
        (bool matched, bytes32 matchedIntentId) = _handleIntent(
            poolId,
            sender,
            params.zeroForOne,
            encAmount,
            encMinReturn
        );

        if (matched) {
            // Intent matched - prevent AMM swap, settlement happens via keeper
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        } else {
            // No match found - let AMM swap proceed normally
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }
    }

    // ─────────────────────────────────────────────
    // Intent Creation & Matching
    // ─────────────────────────────────────────────

    /// @notice Handle intent creation and matching
    function _handleIntent(
        bytes32 poolId,
        address owner,
        bool zeroForOne,
        InEuint128 memory encAmount,
        InEuint128 memory encMinReturn
    ) internal returns (bool matched, bytes32 matchedId) {
        AIMStorage.Storage storage s = AIMStorage.store();

        // Convert client-encrypted inputs to contract euint128/ebool
        euint128 amount = FHE.asEuint128(encAmount);
        euint128 minReturn = FHE.asEuint128(encMinReturn);
        ebool direction = FHE.asEbool(zeroForOne);

        // CRITICAL: Grant contract access to all encrypted values
        FHE.allowThis(amount);
        FHE.allowThis(minReturn);
        FHE.allowThis(direction);

        // Grant sender access to their encrypted data (for unsealing)
        FHE.allow(amount, owner);
        FHE.allow(minReturn, owner);
        FHE.allow(direction, owner);

        // Create new intent
        uint32 created = uint32(block.number);
        uint32 matchWindow = s.defaultMatchWindowBlocks;
        uint32 expire;
        unchecked { expire = created + matchWindow; }

        uint256 nonce = ownerNonces[owner];
        unchecked { ownerNonces[owner] = nonce + 1; }

        bytes32 intentId = AIMStorage.makeIntentId(poolId, owner, nonce, created);

        AIMStorage.Intent memory newIntent = AIMStorage.Intent({
            owner: owner,
            amount: amount,
            minReturn: minReturn,
            zeroForOne: direction,
            createdBlock: created,
            expireBlock: expire,
            status: AIMStorage.IntentStatus.PENDING,
            matchedWith: bytes32(0)
        });

        // Try to find matching intent using FHE comparisons
        (
            bytes32 otherId,
            AIMStorage.Intent storage otherIntent,
            bool found
        ) = AIMMatcher.findMatch(s, poolId, newIntent);

        if (found) {
            // Immediate match (decryption was fast or cached)
            // Store intent, mark both as MATCHED, link them
            AIMStorage.PoolIntents storage pi = s.pools[poolId];
            pi.intents[intentId] = newIntent;
            pi.intents[intentId].status = AIMStorage.IntentStatus.MATCHED;
            pi.intents[intentId].matchedWith = otherId;
            pi.userIntents[owner].push(intentId);

            otherIntent.status = AIMStorage.IntentStatus.MATCHED;
            otherIntent.matchedWith = intentId;

            // Request decryption of amounts for settlement
            FHE.decrypt(amount);
            FHE.decrypt(otherIntent.amount);
            FHE.decrypt(direction);

            // Track decryption requests
            AIMFHE.requestDecryption(s, intentId, amount);
            AIMFHE.requestDecryption(s, otherId, otherIntent.amount);

            emit IntentMatched(poolId, intentId, otherId);
            return (true, otherId);
        } else {
            // No match - store intent in queue for future matching
            AIMStorage.PoolIntents storage pi = s.pools[poolId];
            pi.intents[intentId] = newIntent;
            pi.intentIds.push(intentId);
            pi.userIntents[owner].push(intentId);

            // Request async decryption for future settlement
            FHE.decrypt(amount);
            FHE.decrypt(direction);
            AIMFHE.requestDecryption(s, intentId, amount);

            emit IntentCreated(poolId, intentId, owner, expire);
            return (false, bytes32(0));
        }
    }

    // ─────────────────────────────────────────────
    // Settlement (Keeper-triggered)
    // ─────────────────────────────────────────────

    /// @notice Settle two matched intents after FHE decryption completes
    /// @param poolId The pool ID
    /// @param intentAId First intent ID
    /// @param intentBId Second intent ID
    /// @dev Can be called by anyone (keepers/bots) after decryption resolves
    function settleMatchedIntents(
        bytes32 poolId,
        bytes32 intentAId,
        bytes32 intentBId
    ) external nonReentrant {
        AIMStorage.Storage storage s = AIMStorage.store();
        AIMStorage.Intent storage intentA = s.pools[poolId].intents[intentAId];
        AIMStorage.Intent storage intentB = s.pools[poolId].intents[intentBId];

        // Verify both intents are in MATCHED status
        if (intentA.status != AIMStorage.IntentStatus.MATCHED ||
            intentB.status != AIMStorage.IntentStatus.MATCHED) {
            revert IntentsNotMatched();
        }

        // Execute settlement via AIMSettlement library
        AIMSettlement.settleTwoIntents(
            s,
            poolId,
            poolKeys[poolId],
            intentAId,
            intentA,
            intentBId,
            intentB
        );

        // Get settled amount for event (after settlement updated state)
        (uint128 settledA, ) = AIMFHE.pollDecryption(s, intentAId);

        emit IntentSettled(poolId, intentAId, settledA);
        emit IntentSettled(poolId, intentBId, settledA);
    }

    // ─────────────────────────────────────────────
    // Maintenance
    // ─────────────────────────────────────────────

    /// @notice Cleanup expired intents from a pool
    /// @param poolId The pool to cleanup
    /// @param maxToProcess Maximum number of intents to process (gas bound)
    function cleanupExpired(bytes32 poolId, uint256 maxToProcess) external {
        AIMStorage.Storage storage s = AIMStorage.store();
        AIMStorage.PoolIntents storage pi = s.pools[poolId];

        uint256 processed;
        uint256 i;

        while (i < pi.intentIds.length && processed < maxToProcess) {
            bytes32 id = pi.intentIds[i];
            AIMStorage.Intent storage intent = pi.intents[id];

            if (intent.status == AIMStorage.IntentStatus.PENDING &&
                block.number > intent.expireBlock)
            {
                intent.status = AIMStorage.IntentStatus.EXPIRED;
                emit IntentExpired(poolId, id);

                // Swap-and-pop removal from array
                uint256 lastIndex = pi.intentIds.length - 1;
                if (i != lastIndex) {
                    pi.intentIds[i] = pi.intentIds[lastIndex];
                }
                pi.intentIds.pop();
                unchecked { ++processed; }
                continue; // Don't increment i (new element swapped in)
            }
            unchecked { ++i; }
        }
    }

    // ─────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────

    /// @notice Get intent details
    function getIntent(bytes32 poolId, bytes32 intentId)
        external
        view
        returns (AIMStorage.Intent memory)
    {
        return AIMStorage.store().pools[poolId].intents[intentId];
    }

    /// @notice Get all intent IDs for a user in a pool
    function getUserIntents(bytes32 poolId, address user)
        external
        view
        returns (bytes32[] memory)
    {
        return AIMStorage.store().pools[poolId].userIntents[user];
    }

    /// @notice Get total number of active intents in a pool
    function getPoolIntentCount(bytes32 poolId)
        external
        view
        returns (uint256)
    {
        return AIMStorage.store().pools[poolId].intentIds.length;
    }

    /// @notice Get the matched counterpart for an intent
    function getMatchedIntent(bytes32 poolId, bytes32 intentId)
        external
        view
        returns (bytes32)
    {
        return AIMStorage.store().pools[poolId].intents[intentId].matchedWith;
    }
}
