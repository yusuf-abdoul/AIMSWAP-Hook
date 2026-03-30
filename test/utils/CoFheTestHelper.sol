// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {InEuint128, InEbool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import "../../src/FHEClientHelper.sol";
import "./MockTaskManager.sol";

/// @title CoFheTestHelper
/// @notice Base test contract that deploys a MockTaskManager at the hardcoded
///         TASK_MANAGER_ADDRESS so FHE operations work in unit tests.
/// @dev All test contracts should inherit from this instead of forge Test directly.
///      The mock TaskManager simulates FHE operations with plaintext math,
///      making unit tests fast and deterministic without a real CoFHE coprocessor.
contract CoFheTestHelper is Test {

    // Must match TASK_MANAGER_ADDRESS in cofhe-contracts/FHE.sol
    address constant TASK_MANAGER_ADDR = 0xeA30c4B8b44078Bbf8a6ef5b9f1eC1626C7848D9;

    /// @notice Deploy MockTaskManager at the hardcoded address before each test
    /// @dev Called automatically by setUp() in child contracts.
    ///      Uses vm.etch() to place the mock bytecode at the expected address.
    function _deployMockTaskManager() internal {
        // Deploy mock to a temporary address first
        MockTaskManager mock = new MockTaskManager();
        // Copy its runtime bytecode to the hardcoded address
        vm.etch(TASK_MANAGER_ADDR, address(mock).code);
    }

    /// @notice Must be called at the start of every test setUp()
    constructor() {
        _deployMockTaskManager();
    }

    /// @notice Create a mock InEuint128 for testing
    function createEncryptedUint128(uint128 value, uint256 nonce)
        internal
        pure
        returns (InEuint128 memory)
    {
        return FHEClientHelper.mockEncryptUint128(value, nonce);
    }

    /// @notice Create a mock InEbool for testing
    function createEncryptedBool(bool value, uint256 nonce)
        internal
        pure
        returns (InEbool memory)
    {
        return FHEClientHelper.mockEncryptBool(value, nonce);
    }

    /// @notice Encode hookData from plaintext amounts
    function encodeHookData(
        uint128 amount,
        uint128 minReturn,
        uint256 nonceBase
    ) internal pure returns (bytes memory) {
        InEuint128 memory encAmount = createEncryptedUint128(amount, nonceBase);
        InEuint128 memory encMinReturn = createEncryptedUint128(minReturn, nonceBase + 1);
        return abi.encode(encAmount, encMinReturn);
    }
}
