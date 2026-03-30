// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/// @title CheckPool - Verify pool state on Arbitrum Sepolia or Ethereum Sepolia
/// @notice Usage:
///   POOL_MANAGER=0x... TOKEN0=0x... TOKEN1=0x... AIM_HOOK=0x... \
///   forge script script/CheckPool.s.sol --rpc-url $ARB_SEPOLIA_RPC
contract CheckPool is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    function run() external view {
        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        address hook = vm.envAddress("AIM_HOOK");

        IPoolManager poolManager = IPoolManager(poolManagerAddr);

        // Ensure correct order
        if (uint160(token0) > uint160(token1)) {
            (token0, token1) = (token1, token0);
        }

        console.log("Checking pool:");
        console.log("  PoolManager:", poolManagerAddr);
        console.log("  Token0:", token0);
        console.log("  Token1:", token1);
        console.log("  Hook:", hook);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hook)
        });

        PoolId poolId = poolKey.toId();
        console.log("  Pool ID:", uint256(PoolId.unwrap(poolId)));

        // Check pool slot0 (sqrtPriceX96, tick, etc.)
        (uint160 sqrtPriceX96, int24 tick,,) = poolManager.getSlot0(poolId);

        if (sqrtPriceX96 == 0) {
            console.log("\n  POOL NOT INITIALIZED");
            console.log("  Run: forge script script/InitializePoolWithHook.s.sol --broadcast");
        } else {
            console.log("\n  POOL EXISTS");
            console.log("  sqrtPriceX96:", sqrtPriceX96);
            console.log("  tick:", tick);

            uint128 liquidity = poolManager.getLiquidity(poolId);
            console.log("  liquidity:", liquidity);

            if (liquidity == 0) {
                console.log("  WARNING: No liquidity. Add liquidity before swapping.");
            } else {
                console.log("  Ready to swap!");
            }
        }
    }
}
