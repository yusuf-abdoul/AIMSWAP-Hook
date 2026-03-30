// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FHE, InEuint128, InEbool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/// @title FHEClientHelper
/// @notice Production helpers for FHE client-side encryption integration
/// @dev Use these helpers when integrating with Fhenix client libraries
library FHEClientHelper {
    /// @notice Validate InEuint128 structure before processing
    /// @param input The encrypted input to validate
    /// @return isValid Whether the input has valid structure
    function validateInEuint128(InEuint128 memory input) internal pure returns (bool isValid) {
        // Basic validation checks
        if (input.ctHash == 0) return false;
        if (input.utype != 6) return false; // euint128 has type 6 (EUINT128_TFHE)
        // Additional validation: signature should not be empty in production
        if (input.signature.length == 0) return false;
        return true;
    }

    /// @notice Validate InEbool structure
    /// @param input The encrypted bool input to validate
    /// @return isValid Whether the input has valid structure
    function validateInEbool(InEbool memory input) internal pure returns (bool isValid) {
        if (input.ctHash == 0) return false;
        if (input.utype != 0) return false; // ebool has type 0
        if (input.signature.length == 0) return false;
        return true;
    }

    /// @notice Create a mock encrypted uint128 for testing
    /// @dev DO NOT use in production - only for testing/development
    /// @param value The plaintext value
    /// @param nonce A unique nonce for this encryption
    /// @return Mocked InEuint128 structure
    function mockEncryptUint128(uint128 value, uint256 nonce) internal pure returns (InEuint128 memory) {
        return InEuint128({
            ctHash: uint256(keccak256(abi.encodePacked(value, nonce))),
            securityZone: 0,
            utype: 6, // EUINT128_TFHE
            signature: abi.encode(uint256(value), nonce)
        });
    }

    /// @notice Create a mock encrypted bool for testing
    /// @dev DO NOT use in production - only for testing/development
    /// @param value The plaintext bool value
    /// @param nonce A unique nonce for this encryption
    /// @return Mocked InEbool structure
    function mockEncryptBool(bool value, uint256 nonce) internal pure returns (InEbool memory) {
        return InEbool({
            ctHash: uint256(keccak256(abi.encodePacked(value, nonce))),
            securityZone: 0,
            utype: 0,
            signature: abi.encode(value ? uint256(1) : uint256(0), nonce)
        });
    }

    /// @notice Batch validate multiple encrypted inputs
    /// @param amounts Array of encrypted amounts
    /// @return allValid Whether all inputs are valid
    function batchValidateAmounts(InEuint128[] memory amounts) internal pure returns (bool allValid) {
        for (uint256 i = 0; i < amounts.length; i++) {
            if (!validateInEuint128(amounts[i])) {
                return false;
            }
        }
        return true;
    }

    /// @notice Extract security zone from encrypted input
    /// @param input The encrypted input
    /// @return securityZone The security zone identifier
    function getSecurityZone(InEuint128 memory input) internal pure returns (uint8 securityZone) {
        return input.securityZone;
    }

    /// @notice Check if two encrypted values are from the same security zone
    /// @param a First encrypted value
    /// @param b Second encrypted value
    /// @return sameZone Whether they're from the same zone
    function sameSecurityZone(InEuint128 memory a, InEuint128 memory b) internal pure returns (bool sameZone) {
        return a.securityZone == b.securityZone;
    }
}

/// @title FHEIntentHelper
/// @notice Helper functions for working with encrypted intents
library FHEIntentHelper {
    /// @notice Prepare intent data for submission
    /// @param amount Encrypted amount
    /// @param minReturn Encrypted minimum return
    /// @return hookData Encoded data for hook
    function prepareIntentData(
        InEuint128 memory amount,
        InEuint128 memory minReturn
    ) internal pure returns (bytes memory hookData) {
        return abi.encode(amount, minReturn);
    }

    /// @notice Decode intent data from hookData
    /// @param hookData Encoded hook data
    /// @return amount Encrypted amount
    /// @return minReturn Encrypted minimum return
    function decodeIntentData(bytes memory hookData) internal pure returns (
        InEuint128 memory amount,
        InEuint128 memory minReturn
    ) {
        return abi.decode(hookData, (InEuint128, InEuint128));
    }

    /// @notice Validate complete intent submission
    /// @param amount Encrypted amount
    /// @param minReturn Encrypted minimum return
    /// @return isValid Whether the intent is valid
    /// @return reason Error reason if invalid
    function validateIntent(
        InEuint128 memory amount,
        InEuint128 memory minReturn
    ) internal pure returns (bool isValid, string memory reason) {
        if (!FHEClientHelper.validateInEuint128(amount)) {
            return (false, "Invalid amount encryption");
        }
        if (!FHEClientHelper.validateInEuint128(minReturn)) {
            return (false, "Invalid minReturn encryption");
        }
        if (!FHEClientHelper.sameSecurityZone(amount, minReturn)) {
            return (false, "Security zone mismatch");
        }
        return (true, "");
    }
}
