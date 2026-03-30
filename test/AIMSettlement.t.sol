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
import {InEuint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/AIMHook.sol";
import "../src/AIMStorage.sol";
import "../src/FHEClientHelper.sol";
import "./utils/HookMiner.sol";
import "./utils/CoFheTestHelper.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string public name;
    string public symbol;

    constructor(string memory _name, string memory _symbol) { name = _name; symbol = _symbol; }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function totalSupply() external view returns (uint256) { return _totalSupply; }
    function balanceOf(address account) external view returns (uint256) { return _balances[account]; }
    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount; _balances[to] += amount;
        emit Transfer(msg.sender, to, amount); return true;
    }
    function allowance(address owner, address spender) external view returns (uint256) { return _allowances[owner][spender]; }
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount); return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount; _balances[from] -= amount; _balances[to] += amount;
        emit Transfer(from, to, amount); return true;
    }
}

contract AIMSettlementTest is CoFheTestHelper {
    using PoolIdLibrary for PoolKey;

    AIMHook hook;
    PoolManager poolManager;
    PoolKey poolKey;
    bytes32 poolId;
    MockERC20 token0;
    MockERC20 token1;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token0 = new MockERC20("Token0", "TK0");
        token1 = new MockERC20("Token1", "TK1");
        token0.mint(alice, 100 ether);
        token1.mint(bob, 10000e6);

        poolManager = new PoolManager(address(this));

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        (, bytes32 salt) = HookMiner.find(
            address(this), flags, type(AIMHook).creationCode,
            abi.encode(address(poolManager), uint32(50), uint8(16))
        );

        hook = new AIMHook{salt: salt}(IPoolManager(address(poolManager)), 50, 16);

        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000, tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = PoolId.unwrap(poolKey.toId());

        vm.prank(alice); token0.approve(address(hook), type(uint256).max);
        vm.prank(bob); token1.approve(address(hook), type(uint256).max);
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

    function test_intentCreationAndMatching() public {
        uint256 aliceToken0Before = token0.balanceOf(alice);
        uint256 bobToken1Before = token1.balanceOf(bob);

        _submitIntent(alice, true, 1 ether, 1800e6, 1);
        _submitIntent(bob, false, 1800e6, 0.99 ether, 3);

        assertEq(hook.ownerNonces(alice), 1);
        assertEq(hook.ownerNonces(bob), 1);

        (,,,,IHooks hooks) = hook.poolKeys(poolId);
        assertEq(address(hooks), address(hook));

        // Tokens unchanged before keeper settlement
        assertEq(token0.balanceOf(alice), aliceToken0Before);
        assertEq(token1.balanceOf(bob), bobToken1Before);
    }

    function test_multipleIntentsSequential() public {
        _submitIntent(alice, true, 1 ether, 1800e6, 1);
        _submitIntent(bob, false, 1800e6, 0.99 ether, 3);
        assertEq(hook.ownerNonces(alice), 1);
        assertEq(hook.ownerNonces(bob), 1);
    }

    function test_settlementRequiresMatchedStatus() public {
        vm.expectRevert(AIMHook.IntentsNotMatched.selector);
        hook.settleMatchedIntents(poolId, bytes32(uint256(1)), bytes32(uint256(2)));
    }

    function test_validationHelpers() public pure {
        InEuint128 memory valid = FHEClientHelper.mockEncryptUint128(1 ether, 1);
        assertTrue(FHEClientHelper.validateInEuint128(valid));

        InEuint128 memory invalid = InEuint128({ ctHash: 0, securityZone: 0, utype: 7, signature: hex"1234" });
        assertFalse(FHEClientHelper.validateInEuint128(invalid));
    }
}
