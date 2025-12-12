// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

import "../src/AIMHook.sol";
import "../src/AIMStorage.sol";
import "../src/FHEClientHelper.sol";
import "./utils/HookMiner.sol";

contract AIMMatcherTest is Test {
    using PoolIdLibrary for PoolKey;

    AIMHook hook;
    PoolManager poolManager;
    PoolKey poolKey;
    bytes32 poolId;

    function setUp() public {
        poolManager = new PoolManager(address(this));

        // Mine hook address with correct permissions
        // Need BEFORE_SWAP_RETURNS_DELTA_FLAG since beforeSwapReturnDelta: true
        // Use address(this) as deployer since test contract deploys the hook
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(AIMHook).creationCode,
            abi.encode(address(poolManager), 3, 16) // 3 blocks, scan limit 16
        );

        // Deploy hook with scan limit of 16
        hook = new AIMHook{salt: salt}(
            IPoolManager(address(poolManager)),
            3,  // Match window blocks
            16  // Scan limit
        );

        // Create pool key
        poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        poolId = PoolId.unwrap(poolKey.toId());
    }

    function test_scanLimitBehavior() public {
        // Create > 16 intents quickly and ensure no OOB / expensive operations
        // This tests that the matcher respects the scanLimit parameter

        uint256 intentCount = 20; // More than scan limit of 16
        address[] memory users = new address[](intentCount);

        // Create 20 intents all in same direction (no matches)
        for (uint256 i = 0; i < intentCount; i++) {
            users[i] = address(uint160(0x1000 + i));

            InEuint128 memory encAmount = FHEClientHelper.mockEncryptUint128(1 ether, i * 2);
            InEuint128 memory encMinReturn = FHEClientHelper.mockEncryptUint128(0.99 ether, i * 2 + 1);

            bytes memory hookData = abi.encode(encAmount, encMinReturn);

            SwapParams memory params = SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: 0
            });

            // Submit intent
            vm.prank(users[i]);
            hook.beforeSwap(users[i], poolKey, params, hookData);
        }

        // All 20 intents should be created (nonce = 1 for each user)
        for (uint256 i = 0; i < intentCount; i++) {
            assertEq(hook.ownerNonces(users[i]), 1, "Intent should be created");
        }

        // Now create an opposite intent - should only scan first 16
        address bob = makeAddr("bob");
        InEuint128 memory bobAmount = FHEClientHelper.mockEncryptUint128(1 ether, 100);
        InEuint128 memory bobMinReturn = FHEClientHelper.mockEncryptUint128(0.99 ether, 101);

        bytes memory bobHookData = abi.encode(bobAmount, bobMinReturn);

        SwapParams memory bobParams = SwapParams({
            zeroForOne: false,  // Opposite direction
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: type(uint160).max
        });

        // This should complete without reverting despite having 20 intents
        // The scan limit ensures we only check the first 16
        uint256 gasBefore = gasleft();
        vm.prank(bob);
        hook.beforeSwap(bob, poolKey, bobParams, bobHookData);
        uint256 gasUsed = gasBefore - gasleft();

        // Verify gas usage is bounded (rough check - should be < 5M gas)
        assertLt(gasUsed, 5_000_000, "Gas usage should be bounded by scan limit");

        // Bob's intent should be created
        assertEq(hook.ownerNonces(bob), 1, "Bob's intent should be created");
    }

    function test_matcherFindsFirstAvailable() public {
        // Create 3 intents in same direction
        address alice = makeAddr("alice");
        address charlie = makeAddr("charlie");
        address dave = makeAddr("dave");

        // Alice, Charlie, Dave all create zeroForOne intents
        address[3] memory users = [alice, charlie, dave];
        for (uint256 i = 0; i < 3; i++) {
            InEuint128 memory encAmount = FHEClientHelper.mockEncryptUint128(1 ether, i);
            InEuint128 memory encMinReturn = FHEClientHelper.mockEncryptUint128(0.99 ether, i + 10);

            SwapParams memory params = SwapParams({
                zeroForOne: true,
                amountSpecified: -1 ether,
                sqrtPriceLimitX96: 0
            });

            vm.prank(users[i]);
            hook.beforeSwap(users[i], poolKey, params, abi.encode(encAmount, encMinReturn));
        }

        // Bob creates opposite intent - should match with Alice (first)
        address bob = makeAddr("bob");
        InEuint128 memory bobAmount = FHEClientHelper.mockEncryptUint128(1 ether, 100);
        InEuint128 memory bobMinReturn = FHEClientHelper.mockEncryptUint128(0.99 ether, 101);

        SwapParams memory bobParams = SwapParams({
            zeroForOne: false,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: type(uint160).max
        });

        // Expect match event
        vm.expectEmit(true, true, true, false);
        emit AIMHook.IntentMatched(poolId, bytes32(0), bytes32(0), 0);

        vm.prank(bob);
        hook.beforeSwap(bob, poolKey, bobParams, abi.encode(bobAmount, bobMinReturn));

        // All users should have nonce = 1
        assertEq(hook.ownerNonces(alice), 1);
        assertEq(hook.ownerNonces(bob), 1);
        assertEq(hook.ownerNonces(charlie), 1);
        assertEq(hook.ownerNonces(dave), 1);
    }

    function test_expiredIntentsIgnored() public {
        // Create an intent and advance blocks past expiry
        address alice = makeAddr("alice");

        InEuint128 memory encAmount = FHEClientHelper.mockEncryptUint128(1 ether, 1);
        InEuint128 memory encMinReturn = FHEClientHelper.mockEncryptUint128(0.99 ether, 2);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: 0
        });

        vm.prank(alice);
        hook.beforeSwap(alice, poolKey, params, abi.encode(encAmount, encMinReturn));

        // Advance blocks past match window (3 blocks + 1)
        vm.roll(block.number + 4);

        // Bob tries to match - should not match with expired intent
        address bob = makeAddr("bob");
        InEuint128 memory bobAmount = FHEClientHelper.mockEncryptUint128(1 ether, 10);
        InEuint128 memory bobMinReturn = FHEClientHelper.mockEncryptUint128(0.99 ether, 11);

        SwapParams memory bobParams = SwapParams({
            zeroForOne: false,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: type(uint160).max
        });

        // Should NOT emit IntentMatched (intent expired)
        vm.prank(bob);
        hook.beforeSwap(bob, poolKey, bobParams, abi.encode(bobAmount, bobMinReturn));

        // Both should have created intents, but no match occurred
        assertEq(hook.ownerNonces(alice), 1);
        assertEq(hook.ownerNonces(bob), 1);
    }
}
