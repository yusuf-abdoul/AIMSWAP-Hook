// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../AIMStorage.sol";

/// @title IAIMHook
/// @notice Interface for AIMHook contract
interface IAIMHook {
    /// @notice Get intent details
    /// @param poolId The pool ID
    /// @param intentId The intent ID
    /// @return The intent struct
    function getIntent(bytes32 poolId, bytes32 intentId)
        external
        view
        returns (AIMStorage.Intent memory);

    /// @notice Get all intent IDs for a user in a pool
    /// @param poolId The pool ID
    /// @param user The user address
    /// @return Array of intent IDs
    function getUserIntents(bytes32 poolId, address user)
        external
        view
        returns (bytes32[] memory);

    /// @notice Get total number of active intents in a pool
    /// @param poolId The pool ID
    /// @return Number of intents
    function getPoolIntentCount(bytes32 poolId)
        external
        view
        returns (uint256);

    /// @notice Cleanup expired intents from a pool
    /// @param poolId The pool to cleanup
    /// @param maxToProcess Maximum number of intents to process
    function cleanupExpired(bytes32 poolId, uint256 maxToProcess) external;
}
