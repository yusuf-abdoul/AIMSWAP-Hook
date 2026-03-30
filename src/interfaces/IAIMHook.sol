// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../AIMStorage.sol";

/// @title IAIMHook
/// @notice Interface for AIMHook contract
interface IAIMHook {
    function getIntent(bytes32 poolId, bytes32 intentId)
        external
        view
        returns (AIMStorage.Intent memory);

    function getUserIntents(bytes32 poolId, address user)
        external
        view
        returns (bytes32[] memory);

    function getPoolIntentCount(bytes32 poolId)
        external
        view
        returns (uint256);

    function getMatchedIntent(bytes32 poolId, bytes32 intentId)
        external
        view
        returns (bytes32);

    function cleanupExpired(bytes32 poolId, uint256 maxToProcess) external;

    function settleMatchedIntents(
        bytes32 poolId,
        bytes32 intentAId,
        bytes32 intentBId
    ) external;
}
