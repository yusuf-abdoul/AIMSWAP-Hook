// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/// @title InitializePoolWithHook - Initialize a Uniswap v4 pool with AIMHook
/// @notice Configurable for Arbitrum Sepolia (primary) and Ethereum Sepolia
///
/// Usage:
///   PRIVATE_KEY=0x... \
///   POOL_MANAGER=0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317 \
///   TOKEN0=0x... TOKEN1=0x... AIM_HOOK=0x... \
///   forge script script/InitializePoolWithHook.s.sol --rpc-url $ARB_SEPOLIA_RPC --broadcast
contract InitializePoolWithHook is Script {
    using PoolIdLibrary for PoolKey;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Load addresses from environment (no more hardcoded values)
        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        address hook = vm.envAddress("AIM_HOOK");

        IPoolManager poolManager = IPoolManager(poolManagerAddr);

        // Ensure correct token ordering (required by Uniswap v4)
        if (uint160(token0) > uint160(token1)) {
            (token0, token1) = (token1, token0);
        }

        vm.startBroadcast(deployerPrivateKey);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,       // 0.3%
            tickSpacing: 60,
            hooks: IHooks(hook)
        });

        // Initialize at 1:1 price (sqrtPriceX96 = sqrt(1) * 2^96)
        uint160 sqrtPriceX96 = 79228162514264337593543950336;

        console.log("Initializing pool...");
        console.log("PoolManager:", poolManagerAddr);
        console.log("Token0:", token0);
        console.log("Token1:", token1);
        console.log("Hook:", hook);

        poolManager.initialize(poolKey, sqrtPriceX96);

        bytes32 pid = PoolId.unwrap(poolKey.toId());
        console.log("\n=== POOL INITIALIZED ===");
        console.log("Pool ID:", uint256(pid));

        vm.stopBroadcast();
    }
}
