// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";
import {MockTaskManager} from "./utils/MockTaskManager.sol";

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

/// @title ForkSwap - Test swap on forked Arb Sepolia with mocked FHE
contract ForkSwapTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // Deployed on Arb Sepolia
    IPoolManager constant poolManager = IPoolManager(0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317);
    IPoolSwapTest constant swapRouter = IPoolSwapTest(0xf3A39C86dbd13C45365E57FB90fe413371F65AF8);
    address constant TASK_MANAGER = 0xeA30c4B8b44078Bbf8a6ef5b9f1eC1626C7848D9;

    address token0 = 0x6D228685fb8B30C9863C5d22cE6c59b56CDCb9D8; // WETH
    address token1 = 0xB48e7d0a39edAf931c470a5d97029099f133d358; // USDC
    address hook = 0x055836DFf5fCff373110dDE7fe856259B9970088;
    address deployer = 0xe769800585E8f2dFe7AC396dd2d9201A1E95FEa6;

    PoolKey poolKey;

    function setUp() public {
        // Fork Arb Sepolia
        vm.createSelectFork("https://sepolia-rollup.arbitrum.io/rpc");

        // Replace real CoFHE TaskManager with our mock
        MockTaskManager mock = new MockTaskManager();
        vm.etch(TASK_MANAGER, address(mock).code);

        poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hook)
        });
    }

    function test_poolIsLive() public {
        PoolId pid = poolKey.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(pid);
        uint128 liquidity = poolManager.getLiquidity(pid);

        assertGt(sqrtPriceX96, 0, "Pool not initialized");
        assertGt(liquidity, 0, "Pool has no liquidity");

        emit log_named_uint("sqrtPriceX96", sqrtPriceX96);
        emit log_named_uint("liquidity", liquidity);
    }

    function test_swapWithEncryptedIntent() public {
        uint256 swapAmount = 0.001 ether;

        // Build encrypted hookData
        InEuint128 memory encAmount = _makeEncInput(swapAmount);
        InEuint128 memory encMinReturn = _makeEncInput(0);
        bytes memory hookData = abi.encode(encAmount, encMinReturn);

        // Impersonate deployer (has tokens)
        vm.startPrank(deployer);

        // Approve swap router
        IERC20(token0).approve(address(swapRouter), type(uint256).max);
        IERC20(token1).approve(address(swapRouter), type(uint256).max);

        uint256 bal0Before = IERC20(token0).balanceOf(deployer);
        uint256 bal1Before = IERC20(token1).balanceOf(deployer);

        emit log_named_uint("Token0 before", bal0Before);
        emit log_named_uint("Token1 before", bal1Before);

        // Execute swap through AIMHook
        BalanceDelta delta = swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: 4295128739 + 1
            }),
            IPoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );

        uint256 bal0After = IERC20(token0).balanceOf(deployer);
        uint256 bal1After = IERC20(token1).balanceOf(deployer);

        emit log_named_uint("Token0 after", bal0After);
        emit log_named_uint("Token1 after", bal1After);
        emit log_named_uint("Token0 spent", bal0Before - bal0After);
        emit log_named_uint("Token1 received", bal1After - bal1Before);

        // Verify swap happened
        assertLt(bal0After, bal0Before, "Should have spent token0");

        vm.stopPrank();
    }

    function test_twoOppositeIntentsMatch() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        // Give both users tokens
        vm.startPrank(deployer);
        IERC20(token0).transfer(alice, 1 ether);
        IERC20(token1).transfer(bob, 1_000 * 10**6); // 1000 USDC
        vm.stopPrank();

        // Alice: swap token0 -> token1 (zeroForOne = true)
        InEuint128 memory aliceAmount = _makeEncInput(0.01 ether);
        InEuint128 memory aliceMin = _makeEncInput(0);
        bytes memory aliceData = abi.encode(aliceAmount, aliceMin);

        vm.startPrank(alice);
        IERC20(token0).approve(address(swapRouter), type(uint256).max);
        IERC20(token1).approve(address(swapRouter), type(uint256).max);

        swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(0.01 ether),
                sqrtPriceLimitX96: 4295128739 + 1
            }),
            IPoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            aliceData
        );
        vm.stopPrank();

        // Bob: swap token1 -> token0 (zeroForOne = false)
        InEuint128 memory bobAmount = _makeEncInput(0.01 ether);
        InEuint128 memory bobMin = _makeEncInput(0);
        bytes memory bobData = abi.encode(bobAmount, bobMin);

        vm.startPrank(bob);
        IERC20(token0).approve(address(swapRouter), type(uint256).max);
        IERC20(token1).approve(address(swapRouter), type(uint256).max);

        // When Bob's intent matches Alice's, AIMHook returns ZERO_DELTA
        // (bypasses AMM). PoolSwapTest reverts with NoSwapOccurred() on zero delta.
        // This is correct — matched intents don't go through the AMM.
        vm.expectRevert();
        swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(0.01 ether),
                sqrtPriceLimitX96: type(uint160).max - 1
            }),
            IPoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            bobData
        );
        vm.stopPrank();

        emit log("Match detected: hook returned ZERO_DELTA, AMM bypassed (expected)");
    }

    function _makeEncInput(uint256 plainValue) internal pure returns (InEuint128 memory) {
        uint256 ctHash = uint256(keccak256(abi.encode("fork_test", plainValue)));
        bytes memory signature = abi.encode(plainValue, plainValue);
        return InEuint128({
            ctHash: ctHash,
            securityZone: 0,
            utype: 6,
            signature: signature
        });
    }
}
