// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "test/utils/HookMiner.sol";

import {AIMHook} from "src/AIMHook.sol";

contract DeployScript is Script {
    // CREATE2 Deployer Proxy Address (same across all EVM chains)
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);

        // Get PoolManager address (network-specific)
        address poolManager = vm.envAddress("POOL_MANAGER");
        console.log("PoolManager address:", poolManager);

        // Define hook permissions
        // Need BEFORE_SWAP_RETURNS_DELTA_FLAG since beforeSwapReturnDelta: true
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);

        // Mine salt for CREATE2
        bytes memory creationCode = type(AIMHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            poolManager,
            3, // defaultMatchWindowBlocks
            16 // scanLimit
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            creationCode,
            constructorArgs
        );

        console.log("Deploying AIMHook to:", hookAddress);
        console.log("Using salt:", vm.toString(salt));

        // Deploy hook with private key
        vm.startBroadcast(deployerPrivateKey);

        AIMHook hook = new AIMHook{salt: salt}(
            IPoolManager(poolManager),
            3,
            16
        );

        require(address(hook) == hookAddress, "Hook address mismatch");

        vm.stopBroadcast();

        console.log("AIMHook deployed successfully at:", address(hook));
    }
}
