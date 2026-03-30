// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPoolModifyLiquidityTest {
    struct ModifyLiquidityParams {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        bytes32 salt;
    }

    function modifyLiquidity(
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        bytes memory hookData
    ) external payable;
}

/// @title AddLiquidity - Add liquidity to AIMHook pool on Arbitrum Sepolia
///
/// Usage:
///   source .env && forge script script/AddLiquidity.s.sol \
///     --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
///     --broadcast --slow -vvv
contract AddLiquidity is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Arbitrum Sepolia addresses
    IPoolModifyLiquidityTest constant liquidityRouter =
        IPoolModifyLiquidityTest(0x9A8ca723F5dcCb7926D00B71deC55c2fEa1F50f7);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        address hook = vm.envAddress("AIM_HOOK");

        // Ensure correct ordering
        if (uint160(token0) > uint160(token1)) {
            (token0, token1) = (token1, token0);
        }

        console.log("=== Adding Liquidity ===");
        console.log("Deployer:", deployer);
        console.log("Token0:", token0);
        console.log("Token1:", token1);
        console.log("Hook:", hook);
        console.log("LiquidityRouter:", address(liquidityRouter));

        uint256 balance0 = IERC20(token0).balanceOf(deployer);
        uint256 balance1 = IERC20(token1).balanceOf(deployer);
        console.log("Balance token0:", balance0);
        console.log("Balance token1:", balance1);

        vm.startBroadcast(deployerPrivateKey);

        // Approve tokens for liquidity router
        IERC20(token0).approve(address(liquidityRouter), type(uint256).max);
        IERC20(token1).approve(address(liquidityRouter), type(uint256).max);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hook)
        });

        // Add liquidity in a range around tick 0 (1:1 price)
        int24 tickLower = -600;
        int24 tickUpper = 600;
        int256 liquidityDelta = 1_000_000_000; // Reasonable amount

        console.log("\nAdding liquidity...");

        liquidityRouter.modifyLiquidity(
            poolKey,
            IPoolModifyLiquidityTest.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: bytes32(0)
            }),
            ""
        );

        console.log("\n=== LIQUIDITY ADDED ===");
        console.log("Pool is ready for swaps!");

        vm.stopBroadcast();
    }
}
