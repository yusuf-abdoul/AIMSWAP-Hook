// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "test/utils/HookMiner.sol";

import {AIMHook} from "src/AIMHook.sol";

/// @title DeployScript - Deploy AIMHook to Arbitrum Sepolia or Ethereum Sepolia
/// @notice Uses CREATE2 for deterministic hook addresses with correct permission flags.
///
/// Usage:
///   ARB_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc \
///   PRIVATE_KEY=0x... \
///   POOL_MANAGER=0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317 \
///   forge script script/Deploy.s.sol --rpc-url $ARB_SEPOLIA_RPC --broadcast
contract DeployScript is Script {
    // CREATE2 Deployer Proxy Address (same across all EVM chains)
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);

        // Get PoolManager address (network-specific)
        // Arbitrum Sepolia: 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317
        // Ethereum Sepolia: 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
        address poolManager = vm.envAddress("POOL_MANAGER");
        console.log("PoolManager address:", poolManager);

        // Define hook permissions
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);

        // Constructor args
        uint32 matchWindowBlocks = 50;  // ~50 blocks for FHE decryption time
        uint8 scanLimit = 16;

        bytes memory creationCode = type(AIMHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            poolManager,
            matchWindowBlocks,
            scanLimit
        );

        // Mine salt for CREATE2 deterministic address
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            creationCode,
            constructorArgs
        );

        console.log("Deploying AIMHook to:", hookAddress);
        console.log("Using salt:", vm.toString(salt));

        vm.startBroadcast(deployerPrivateKey);

        AIMHook hook = new AIMHook{salt: salt}(
            IPoolManager(poolManager),
            matchWindowBlocks,
            scanLimit
        );

        require(address(hook) == hookAddress, "Hook address mismatch");

        vm.stopBroadcast();

        console.log("AIMHook deployed successfully at:", address(hook));
        console.log("Match window:", matchWindowBlocks, "blocks");
        console.log("Scan limit:", scanLimit, "intents");
    }
}
