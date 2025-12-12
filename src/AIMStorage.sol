// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FHE, euint128, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

// @title AIMStorage
// @notice Packed storage & helpers for AIM Hook
library AIMStorage {
    /// @notice Intent status enum for clarity and type safety
    enum IntentStatus {
        PENDING,   // 0 - Intent created, awaiting match
        MATCHED,   // 1 - Match found, awaiting settlement
        SETTLED,   // 2 - Successfully settled
        EXPIRED    // 3 - Expired without match
    }

    struct Intent {
        address owner;
        euint128 amount; // input token amount (encrypted)
        euint128 minReturn; // minimum return amount (encrypted)
        ebool zeroForOne; // swap direction (encrypted)
        uint32 createdBlock;
        uint32 expireBlock;
        IntentStatus status; // Intent lifecycle status
        uint256 decryptHandle; // handle for async decryption tracking
    }

    struct PoolIntents {
        bytes32[] intentIds; // Array of intent IDs (FIFO queue)
        mapping(bytes32 => Intent) intents; // intentId -> Intent
        mapping(address => bytes32[]) userIntents; // user -> intentIds
    }

    // Top-level mapping stored in the hook contract
    struct Storage {
        mapping(bytes32 => PoolIntents) pools; // poolId -> PoolIntents
        uint32 defaultMatchWindowBlocks;
        uint8 scanLimit; // max intents to scan (default: 16)
        uint8 partialMatchLimit; // limit partial matches per submission
        uint256 minDepositWei; // spam protection (if used)
        euint128 ENCRYPTED_ZERO; // encrypted zero constant for FHE.select
    }

    bytes32 internal constant AIM_STORAGE_SLOT = keccak256("aim.storage.slot");

    function store() internal pure returns (Storage storage s) {
        bytes32 slot = AIM_STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /// @notice Create intent ID using optimized assembly keccak256
    /// @dev Using assembly for gas optimization
    function makeIntentId(
        bytes32 poolId,
        address owner,
        uint256 nonce,
        uint32 createdBlock
    ) internal pure returns (bytes32 result) {
        assembly {
            // Store values in memory for hashing
            let ptr := mload(0x40)
            mstore(ptr, poolId)
            mstore(add(ptr, 0x20), owner)
            mstore(add(ptr, 0x40), nonce)
            mstore(add(ptr, 0x60), createdBlock)
            result := keccak256(ptr, 0x80)
        }
    }
}
