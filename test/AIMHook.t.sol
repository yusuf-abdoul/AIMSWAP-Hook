// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {
    FHE,
    euint128,
    ebool,
    InEuint128,
    InEbool
} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

import "../src/AIMHook.sol";
import "../src/AIMStorage.sol";
import "../src/FHEClientHelper.sol";
import "./utils/HookMiner.sol";

contract AIMHookTest is Test {
    using PoolIdLibrary for PoolKey;

    PoolManager poolManager;
    AIMHook hook;
    PoolKey poolKey;
    bytes32 poolId;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    /// @notice Helper to create InEuint128 for testing
    /// @dev Uses FHEClientHelper for mock encryption
    function createInEuint128(uint128 value, uint256 nonce) internal pure returns (InEuint128 memory) {
        return FHEClientHelper.mockEncryptUint128(value, nonce);
    }

    /// @notice Helper to create InEbool for testing
    function createInEbool(bool value, uint256 nonce) internal pure returns (InEbool memory) {
        return FHEClientHelper.mockEncryptBool(value, nonce);
    }

    function setUp() public {
        // Deploy PoolManager
        poolManager = new PoolManager(address(this));

        // Mine hook address with correct permissions
        // Need BEFORE_SWAP_RETURNS_DELTA_FLAG since beforeSwapReturnDelta: true
        // Use address(this) as deployer since test contract deploys the hook
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(AIMHook).creationCode,
            abi.encode(address(poolManager), 3, 16) // 3 blocks, scan 16
        );

        // Deploy hook
        hook = new AIMHook{salt: salt}(
            poolManager,
            3, // Match window: 3 blocks
            16 // Scan limit: 16 intents
        );

        // Create pool key (simplified - in production would need actual tokens)
        poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        poolId = PoolId.unwrap(poolKey.toId());
    }

    function test_createIntent_storesEncrypted() public {
        // Create encrypted amount (client-side simulation)
        InEuint128 memory encAmount = createInEuint128(1 ether, 1);
        InEuint128 memory encMinReturn = createInEuint128(0.99 ether, 2);

        // Validate input using FHEClientHelper
        assertTrue(FHEClientHelper.validateInEuint128(encAmount), "Amount validation failed");
        assertTrue(FHEClientHelper.validateInEuint128(encMinReturn), "MinReturn validation failed");

        // Encode hookData
        bytes memory hookData = abi.encode(encAmount, encMinReturn);

        // Create swap params
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: 0
        });

        // Trigger beforeSwap which creates intent
        vm.prank(alice);
        (bytes4 selector, , ) = hook.beforeSwap(alice, poolKey, params, hookData);

        // Verify beforeSwap executed
        assertEq(selector, BaseHook.beforeSwap.selector, "Incorrect selector returned");

        // Verify intent was stored (check nonce increased)
        uint256 aliceNonce = hook.ownerNonces(alice);
        assertEq(aliceNonce, 1, "Owner nonce should increment to 1");
    }

    function test_matchOppositeIntents() public {
        // Alice creates intent: 1 ETH -> Token (zeroForOne = true)
        InEuint128 memory aliceAmount = createInEuint128(1 ether, 1);
        InEuint128 memory aliceMinReturn = createInEuint128(1800e6, 2);

        bytes memory aliceHookData = abi.encode(aliceAmount, aliceMinReturn);

        SwapParams memory aliceParams = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: 0
        });

        // Alice submits first intent (no match yet)
        vm.prank(alice);
        (bytes4 selector1, , ) = hook.beforeSwap(alice, poolKey, aliceParams, aliceHookData);
        assertEq(selector1, BaseHook.beforeSwap.selector, "Alice intent creation failed");

        // Bob creates opposite intent: Token -> ETH (zeroForOne = false)
        InEuint128 memory bobAmount = createInEuint128(1800e6, 3);
        InEuint128 memory bobMinReturn = createInEuint128(0.99 ether, 4);

        bytes memory bobHookData = abi.encode(bobAmount, bobMinReturn);

        SwapParams memory bobParams = SwapParams({
            zeroForOne: false,
            amountSpecified: -1800e6,
            sqrtPriceLimitX96: type(uint160).max
        });

        // Expect IntentMatched event
        vm.expectEmit(true, true, true, false);
        emit AIMHook.IntentMatched(poolId, bytes32(0), bytes32(0), 0);

        // Bob submits opposite intent - should match with Alice
        vm.prank(bob);
        (bytes4 selector2, , ) = hook.beforeSwap(bob, poolKey, bobParams, bobHookData);
        assertEq(selector2, BaseHook.beforeSwap.selector, "Bob intent submission failed");

        // Both nonces should have incremented
        assertEq(hook.ownerNonces(alice), 1, "Alice nonce incorrect");
        assertEq(hook.ownerNonces(bob), 1, "Bob nonce incorrect");

        // PoolKey should be stored for settlement
        (Currency currency0, Currency currency1, uint24 fee, int24 tickSpacing, IHooks hooks) = hook.poolKeys(poolId);
        assertEq(address(hooks), address(hook), "PoolKey not stored correctly");
    }

    function test_noMatch_fallsBackToAMM() public {
        // Create intent with no opposite
        InEuint128 memory encAmount = createInEuint128(1 ether, 1);
        InEuint128 memory encMinReturn = createInEuint128(0.99 ether, 2);

        bytes memory hookData = abi.encode(encAmount, encMinReturn);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: 0
        });

        // Submit intent (no match exists)
        vm.prank(alice);
        (bytes4 selector, , ) = hook.beforeSwap(alice, poolKey, params, hookData);

        // Should return normally - intent stored, no match found
        assertEq(selector, BaseHook.beforeSwap.selector, "beforeSwap should succeed");

        // Intent should be created (nonce incremented)
        assertEq(hook.ownerNonces(alice), 1, "Intent should be stored");

        // In a real scenario, this would fall through to AMM swap
        // Here we're verifying the hook doesn't prevent the swap
    }

    function test_validateIntentHelper() public pure {
        // Test FHEIntentHelper validation
        InEuint128 memory validAmount = FHEClientHelper.mockEncryptUint128(1 ether, 1);
        InEuint128 memory validMinReturn = FHEClientHelper.mockEncryptUint128(0.99 ether, 2);

        (bool isValid, string memory reason) = FHEIntentHelper.validateIntent(
            validAmount,
            validMinReturn
        );

        assertTrue(isValid, "Valid intent should pass validation");
        assertEq(bytes(reason).length, 0, "No error reason expected");
    }

    function test_validateIntentHelper_invalidAmount() public pure {
        // Create invalid amount (ctHash = 0)
        InEuint128 memory invalidAmount = InEuint128({
            ctHash: 0,
            securityZone: 0,
            utype: 7,
            signature: hex"1234"
        });

        InEuint128 memory validMinReturn = FHEClientHelper.mockEncryptUint128(0.99 ether, 2);

        (bool isValid, string memory reason) = FHEIntentHelper.validateIntent(
            invalidAmount,
            validMinReturn
        );

        assertFalse(isValid, "Invalid intent should fail validation");
        assertEq(reason, "Invalid amount encryption", "Wrong error reason");
    }

    /// @notice Example FHE transfer function (for reference)
    /// @dev Shows how FHE operations can be used for conditional logic
    function exampleTransfer(euint128 balance, euint128 amount) internal returns (euint128) {
        ebool canTransfer = FHE.gte(balance, amount);

        euint128 newBalance = FHE.select(
            canTransfer,
            FHE.sub(balance, amount), // Transfer succeeds
            balance // Transfer fails, keep balance
        );

        return newBalance;
    }
}
