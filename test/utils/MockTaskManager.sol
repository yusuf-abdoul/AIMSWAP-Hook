// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ITaskManager, FunctionId, EncryptedInput} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";

/// @title MockTaskManager
/// @notice Mock implementation of the CoFHE TaskManager for unit tests.
/// @dev Deployed at the hardcoded TASK_MANAGER_ADDRESS (0xeA30c4B8b44078Bbf8a6ef5b9f1eC1626C7848D9)
///      using vm.etch() in test setUp().
///
///      This mock:
///      - Returns deterministic ctHash values from createTask (hash of inputs)
///      - Tracks permissions via allow()/isAllowed()
///      - Returns plaintext values for decrypt results (simulates instant decryption)
///      - Validates encrypted inputs by returning ctHash directly
contract MockTaskManager is ITaskManager {
    // Nonce for generating unique ctHashes
    uint256 private _nonce;

    // Permission tracking: ctHash => address => allowed
    mapping(uint256 => mapping(address => bool)) private _permissions;

    // Decrypt results: ctHash => (result, isReady)
    mapping(uint256 => uint256) private _decryptResults;
    mapping(uint256 => bool) private _decryptReady;

    // Store original values for trivialEncrypt: ctHash => plaintext
    mapping(uint256 => uint256) private _plaintexts;

    function createTask(
        uint8 /* returnType */,
        FunctionId funcId,
        uint256[] memory encryptedInputs,
        uint256[] memory extraInputs
    ) external override returns (uint256) {
        unchecked { ++_nonce; }

        // Generate deterministic ctHash
        uint256 ctHash = uint256(keccak256(abi.encode(_nonce, funcId, encryptedInputs, extraInputs)));

        // For trivialEncrypt, store the plaintext value
        if (funcId == FunctionId.trivialEncrypt && extraInputs.length >= 1) {
            _plaintexts[ctHash] = extraInputs[0];
            // Auto-resolve decrypt for trivial values
            _decryptResults[ctHash] = extraInputs[0];
            _decryptReady[ctHash] = true;
        }

        // For binary operations, compute mock result
        // Uses unchecked to mirror FHE behavior (encrypted ops don't revert on overflow)
        if (encryptedInputs.length == 2) {
            uint256 a = _plaintexts[encryptedInputs[0]];
            uint256 b = _plaintexts[encryptedInputs[1]];
            uint256 result;

            unchecked {
                if (funcId == FunctionId.add) result = a + b;
                else if (funcId == FunctionId.sub) result = a > b ? a - b : 0;
                else if (funcId == FunctionId.mul) result = a * b;
                else if (funcId == FunctionId.div) result = b > 0 ? a / b : 0;
                else if (funcId == FunctionId.gt) result = a > b ? 1 : 0;
                else if (funcId == FunctionId.lt) result = a < b ? 1 : 0;
                else if (funcId == FunctionId.gte) result = a >= b ? 1 : 0;
                else if (funcId == FunctionId.lte) result = a <= b ? 1 : 0;
                else if (funcId == FunctionId.eq) result = a == b ? 1 : 0;
                else if (funcId == FunctionId.xor) result = a ^ b;
                else if (funcId == FunctionId.and) result = a & b;
                else if (funcId == FunctionId.or) result = a | b;
                else if (funcId == FunctionId.min) result = a < b ? a : b;
                else if (funcId == FunctionId.max) result = a > b ? a : b;
                else result = ctHash; // fallback
            }

            _plaintexts[ctHash] = result;
            _decryptResults[ctHash] = result;
            _decryptReady[ctHash] = true;
        }

        // For select (ternary): condition, ifTrue, ifFalse
        if (funcId == FunctionId.select && encryptedInputs.length == 3) {
            uint256 cond = _plaintexts[encryptedInputs[0]];
            uint256 ifTrue = _plaintexts[encryptedInputs[1]];
            uint256 ifFalse = _plaintexts[encryptedInputs[2]];
            uint256 result = cond != 0 ? ifTrue : ifFalse;
            _plaintexts[ctHash] = result;
            _decryptResults[ctHash] = result;
            _decryptReady[ctHash] = true;
        }

        return ctHash;
    }

    function createDecryptTask(uint256 ctHash, address /* requestor */) external override {
        // In mock, decryption is instant - result already set from createTask
        if (!_decryptReady[ctHash]) {
            _decryptResults[ctHash] = _plaintexts[ctHash];
            _decryptReady[ctHash] = true;
        }
    }

    function verifyInput(EncryptedInput memory input, address /* sender */) external override returns (uint256) {
        uint256 ctHash = input.ctHash;
        // Decode actual plaintext from signature (mock encoding from FHEClientHelper)
        if (input.signature.length >= 64) {
            (uint256 plainValue,) = abi.decode(input.signature, (uint256, uint256));
            _plaintexts[ctHash] = plainValue;
            _decryptResults[ctHash] = plainValue;
        } else {
            _plaintexts[ctHash] = 0;
            _decryptResults[ctHash] = 0;
        }
        _decryptReady[ctHash] = true;
        return ctHash;
    }

    function allow(uint256 ctHash, address account) external override {
        _permissions[ctHash][account] = true;
    }

    function isAllowed(uint256 ctHash, address account) external view override returns (bool) {
        return _permissions[ctHash][account];
    }

    function allowGlobal(uint256 /* ctHash */) external override {
        // No-op in mock
    }

    function allowTransient(uint256 ctHash, address account) external override {
        _permissions[ctHash][account] = true;
    }

    function getDecryptResultSafe(uint256 ctHash) external view override returns (uint256, bool) {
        return (_decryptResults[ctHash], _decryptReady[ctHash]);
    }

    function getDecryptResult(uint256 ctHash) external view override returns (uint256) {
        require(_decryptReady[ctHash], "Not decrypted");
        return _decryptResults[ctHash];
    }
}
