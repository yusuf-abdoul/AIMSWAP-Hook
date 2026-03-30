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

import "../src/AIMHook.sol";
import "../src/AIMStorage.sol";
import "./utils/HookMiner.sol";
import "./utils/CoFheTestHelper.sol";

contract AIMMatcherTest is CoFheTestHelper {
    using PoolIdLibrary for PoolKey;

    AIMHook hook;
    PoolManager poolManager;
    PoolKey poolKey;
    bytes32 poolId;

    function setUp() public {
        poolManager = new PoolManager(address(this));

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        (, bytes32 salt) = HookMiner.find(
            address(this), flags, type(AIMHook).creationCode,
            abi.encode(address(poolManager), uint32(50), uint8(16))
        );

        hook = new AIMHook{salt: salt}(IPoolManager(address(poolManager)), 50, 16);

        poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(1)),
            fee: 3000, tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = PoolId.unwrap(poolKey.toId());
    }

    function _submitIntent(address user, bool zeroForOne, uint128 amount, uint128 minReturn, uint256 nonceBase) internal {
        bytes memory hookData = encodeHookData(amount, minReturn, nonceBase);
        vm.prank(address(poolManager));
        hook.beforeSwap(
            user, poolKey,
            SwapParams({ zeroForOne: zeroForOne, amountSpecified: -int256(uint256(amount)), sqrtPriceLimitX96: zeroForOne ? 0 : type(uint160).max }),
            hookData
        );
    }

    function test_scanLimitBehavior() public {
        uint256 intentCount = 20;
        address[] memory users = new address[](intentCount);

        for (uint256 i = 0; i < intentCount; i++) {
            users[i] = address(uint160(0x1000 + i));
            _submitIntent(users[i], true, 1 ether, 0.99 ether, i * 2);
        }

        for (uint256 i = 0; i < intentCount; i++) {
            assertEq(hook.ownerNonces(users[i]), 1);
        }

        address bob = makeAddr("bob");
        uint256 gasBefore = gasleft();
        _submitIntent(bob, false, 1 ether, 0.99 ether, 100);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 5_000_000);
        assertEq(hook.ownerNonces(bob), 1);
    }

    function test_matcherFindsFirstAvailable() public {
        address alice = makeAddr("alice");
        address charlie = makeAddr("charlie");
        address dave = makeAddr("dave");

        _submitIntent(alice, true, 1 ether, 0.99 ether, 0);
        _submitIntent(charlie, true, 1 ether, 0.99 ether, 10);
        _submitIntent(dave, true, 1 ether, 0.99 ether, 20);

        address bob = makeAddr("bob");
        _submitIntent(bob, false, 1 ether, 0.99 ether, 100);

        assertEq(hook.ownerNonces(alice), 1);
        assertEq(hook.ownerNonces(bob), 1);
    }

    function test_expiredIntentsIgnored() public {
        address alice = makeAddr("alice");
        _submitIntent(alice, true, 1 ether, 0.99 ether, 1);

        vm.roll(block.number + 51);

        address bob = makeAddr("bob");
        _submitIntent(bob, false, 1 ether, 0.99 ether, 10);

        assertEq(hook.ownerNonces(alice), 1);
        assertEq(hook.ownerNonces(bob), 1);
    }

    function test_cleanupExpired() public {
        address alice = makeAddr("alice");
        _submitIntent(alice, true, 1 ether, 0.99 ether, 1);
        assertEq(hook.getPoolIntentCount(poolId), 1);

        vm.roll(block.number + 51);
        hook.cleanupExpired(poolId, 10);
        assertEq(hook.getPoolIntentCount(poolId), 0);
    }
}
