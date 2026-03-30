// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

import "../src/AIMHook.sol";
import "../src/AIMStorage.sol";
import "../src/FHEClientHelper.sol";
import "./utils/HookMiner.sol";
import "./utils/CoFheTestHelper.sol";

contract AIMHookTest is CoFheTestHelper {
    using PoolIdLibrary for PoolKey;

    PoolManager poolManager;
    AIMHook hook;
    PoolKey poolKey;
    bytes32 poolId;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        poolManager = new PoolManager(address(this));

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        (, bytes32 salt) = HookMiner.find(
            address(this), flags, type(AIMHook).creationCode,
            abi.encode(address(poolManager), uint32(50), uint8(16))
        );

        hook = new AIMHook{salt: salt}(poolManager, 50, 16);

        poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(1)),
            fee: 3000, tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = PoolId.unwrap(poolKey.toId());
    }

    /// @dev Helper: call beforeSwap as the PoolManager (required by onlyPoolManager modifier)
    function _callBeforeSwap(address sender, bool zeroForOne, uint128 amount, uint128 minReturn, uint256 nonceBase)
        internal returns (bytes4 selector)
    {
        bytes memory hookData = encodeHookData(amount, minReturn, nonceBase);
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(uint256(amount)),
            sqrtPriceLimitX96: zeroForOne ? 0 : type(uint160).max
        });
        vm.prank(address(poolManager));
        (selector, , ) = hook.beforeSwap(sender, poolKey, params, hookData);
    }

    function test_createIntent_storesEncrypted() public {
        bytes4 sel = _callBeforeSwap(alice, true, 1 ether, 0.99 ether, 1);
        assertEq(sel, BaseHook.beforeSwap.selector);
        assertEq(hook.ownerNonces(alice), 1);
    }

    function test_matchOppositeIntents() public {
        _callBeforeSwap(alice, true, 1 ether, 1800e6, 1);
        _callBeforeSwap(bob, false, 1800e6, 0.99 ether, 3);

        assertEq(hook.ownerNonces(alice), 1);
        assertEq(hook.ownerNonces(bob), 1);

        (,,,,IHooks hooks) = hook.poolKeys(poolId);
        assertEq(address(hooks), address(hook));
    }

    function test_noMatch_fallsBackToAMM() public {
        bytes4 sel = _callBeforeSwap(alice, true, 1 ether, 0.99 ether, 1);
        assertEq(sel, BaseHook.beforeSwap.selector);
        assertEq(hook.ownerNonces(alice), 1);
    }

    function test_invalidEncryptedInput_reverts() public {
        InEuint128 memory invalidAmount = InEuint128({ ctHash: 0, securityZone: 0, utype: 7, signature: hex"1234" });
        InEuint128 memory validMinReturn = createEncryptedUint128(0.99 ether, 2);
        bytes memory hookData = abi.encode(invalidAmount, validMinReturn);

        SwapParams memory params = SwapParams({ zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: 0 });

        vm.prank(address(poolManager));
        vm.expectRevert(AIMHook.InvalidEncryptedInput.selector);
        hook.beforeSwap(alice, poolKey, params, hookData);
    }

    function test_validateIntentHelper() public pure {
        InEuint128 memory validAmount = FHEClientHelper.mockEncryptUint128(1 ether, 1);
        InEuint128 memory validMinReturn = FHEClientHelper.mockEncryptUint128(0.99 ether, 2);
        (bool isValid, string memory reason) = FHEIntentHelper.validateIntent(validAmount, validMinReturn);
        assertTrue(isValid);
        assertEq(bytes(reason).length, 0);
    }

    function test_getMatchedIntent() public {
        _callBeforeSwap(alice, true, 1 ether, 0.99 ether, 1);
        _callBeforeSwap(bob, false, 1 ether, 0.99 ether, 3);
        assertEq(hook.ownerNonces(alice), 1);
        assertEq(hook.ownerNonces(bob), 1);
    }
}
