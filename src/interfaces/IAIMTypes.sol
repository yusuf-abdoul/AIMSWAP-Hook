// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {euint128, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/// @title IAIMTypes
/// @notice Common types and enums for AIM system
interface IAIMTypes {
    /// @notice Intent status enum
    enum IntentStatus {
        PENDING,   // Intent created, awaiting match
        MATCHED,   // Match found, awaiting settlement
        SETTLED,   // Successfully settled
        EXPIRED    // Expired without match
    }
}
