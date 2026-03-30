// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";

interface IPoolSwapTest {
    struct TestSettings {
        bool takeClaims;
        bool settleUsingBurn;
    }

    function swap(
        PoolKey memory key,
        SwapParams memory params,
        TestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta);
}

/// @title TestSwap - Test a swap through AIMHook on Arbitrum Sepolia
///
/// Usage:
///   source .env && forge script script/TestSwap.s.sol \
///     --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
///     --broadcast --slow -vvv
contract TestSwap is Script {
    // Arb Sepolia PoolSwapTest
    IPoolSwapTest constant swapRouter =
        IPoolSwapTest(0xf3A39C86dbd13C45365E57FB90fe413371F65AF8);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        address hook = vm.envAddress("AIM_HOOK");

        // Sort tokens
        if (uint160(token0) > uint160(token1)) {
            (token0, token1) = (token1, token0);
        }

        console.log("=== Test Swap via AIMHook ===");
        console.log("Deployer:", deployer);
        console.log("Token0:", token0);
        console.log("Token1:", token1);
        console.log("Hook:", hook);

        // Check balances before
        uint256 bal0Before = IERC20(token0).balanceOf(deployer);
        uint256 bal1Before = IERC20(token1).balanceOf(deployer);
        console.log("\nBalances before:");
        console.log("  Token0:", bal0Before);
        console.log("  Token1:", bal1Before);

        vm.startBroadcast(deployerPrivateKey);

        // Approve swap router
        IERC20(token0).approve(address(swapRouter), type(uint256).max);
        IERC20(token1).approve(address(swapRouter), type(uint256).max);

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hook)
        });

        // Build encrypted hookData
        // For testnet: create InEuint128 structs that pass validation
        // utype=6 (EUINT128_TFHE), ctHash and signature from CoFHE
        uint256 swapAmount = 0.001 ether; // Small test swap

        InEuint128 memory encAmount = _makeTestEncInput(swapAmount);
        InEuint128 memory encMinReturn = _makeTestEncInput(0); // no minimum

        bytes memory hookData = abi.encode(encAmount, encMinReturn);

        console.log("\nExecuting swap (zeroForOne, 0.001 tokens)...");

        // Swap: zeroForOne = true, exact input
        BalanceDelta delta = swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount), // negative = exact input
                sqrtPriceLimitX96: 4295128739 + 1 // min price for zeroForOne
            }),
            IPoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        vm.stopBroadcast();

        // Check balances after
        uint256 bal0After = IERC20(token0).balanceOf(deployer);
        uint256 bal1After = IERC20(token1).balanceOf(deployer);
        console.log("\nBalances after:");
        console.log("  Token0:", bal0After);
        console.log("  Token1:", bal1After);
        console.log("\n=== SWAP SUCCESSFUL ===");
    }

    /// @dev Create a test InEuint128 that passes FHEClientHelper.validateInEuint128()
    /// On testnet, the CoFHE TaskManager.verifyInput() will process it
    function _makeTestEncInput(uint256 plainValue) internal pure returns (InEuint128 memory) {
        // ctHash: deterministic from plainValue
        uint256 ctHash = uint256(keccak256(abi.encode("test_input", plainValue)));

        // Signature encodes the plaintext (64+ bytes for CoFHE verification)
        bytes memory signature = abi.encode(plainValue, plainValue);

        return InEuint128({
            ctHash: ctHash,
            securityZone: 0,
            utype: 6, // EUINT128_TFHE
            signature: signature
        });
    }
}
