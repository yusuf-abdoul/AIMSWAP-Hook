// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HookMiner} from "test/utils/HookMiner.sol";
import {AIMHook} from "src/AIMHook.sol";
import {TestToken} from "src/tokens/TestToken.sol";

/// @title DeployAll - Full deployment to Arbitrum Sepolia
/// @notice Deploys tokens, hook, initializes pool in one script.
///
/// Usage:
///   source .env && forge script script/DeployAll.s.sol \
///     --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
///     --broadcast --slow -vvv
contract DeployAll is Script {
    using PoolIdLibrary for PoolKey;

    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address poolManagerAddr = vm.envAddress("POOL_MANAGER");

        console.log("=== AIMHook Full Deployment ===");
        console.log("Deployer:", deployer);
        console.log("PoolManager:", poolManagerAddr);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // --- Step 1: Deploy Test Tokens ---
        TestToken weth = new TestToken("Wrapped Ether", "WETH", 18);
        TestToken usdc = new TestToken("USD Coin", "USDC", 6);

        console.log("\n--- Tokens Deployed ---");
        console.log("WETH:", address(weth));
        console.log("USDC:", address(usdc));

        // Mint test tokens to deployer
        weth.mint(deployer, 100 ether);
        usdc.mint(deployer, 100_000 * 10 ** 6); // 100k USDC
        console.log("Minted 100 WETH and 100,000 USDC to deployer");

        vm.stopBroadcast();

        // --- Step 2: Deploy AIMHook with CREATE2 ---
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        uint32 matchWindowBlocks = 50;
        uint8 scanLimit = 16;

        bytes memory creationCode = type(AIMHook).creationCode;
        bytes memory constructorArgs = abi.encode(poolManagerAddr, matchWindowBlocks, scanLimit);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            creationCode,
            constructorArgs
        );

        console.log("\n--- Hook Deployment ---");
        console.log("Target hook address:", hookAddress);
        console.log("Salt:", vm.toString(salt));

        vm.startBroadcast(deployerPrivateKey);

        AIMHook hook = new AIMHook{salt: salt}(
            IPoolManager(poolManagerAddr),
            matchWindowBlocks,
            scanLimit
        );
        require(address(hook) == hookAddress, "Hook address mismatch");

        console.log("AIMHook deployed at:", address(hook));

        // --- Step 3: Initialize Pool ---
        // Sort tokens (Uniswap v4 requires token0 < token1)
        address token0;
        address token1;
        if (uint160(address(weth)) < uint160(address(usdc))) {
            token0 = address(weth);
            token1 = address(usdc);
        } else {
            token0 = address(usdc);
            token1 = address(weth);
        }

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // Initialize at 1:1 price (sqrtPriceX96 for tick 0)
        uint160 sqrtPriceX96 = 79228162514264337593543950336;

        IPoolManager(poolManagerAddr).initialize(poolKey, sqrtPriceX96);

        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        console.log("\n--- Pool Initialized ---");
        console.log("Token0:", token0);
        console.log("Token1:", token1);
        console.log("Pool ID:", vm.toString(poolId));

        vm.stopBroadcast();

        // --- Summary ---
        console.log("\n========================================");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("========================================");
        console.log("WETH:     ", address(weth));
        console.log("USDC:     ", address(usdc));
        console.log("AIMHook:  ", address(hook));
        console.log("Pool ID:  ", vm.toString(poolId));
        console.log("Chain:     Arbitrum Sepolia (421614)");
        console.log("========================================");
        console.log("");
        console.log("Next steps:");
        console.log("1. Update .env with TOKEN0, TOKEN1, AIM_HOOK");
        console.log("2. Deploy a liquidity router or use PositionManager");
        console.log("3. Add liquidity to the pool");
    }
}
