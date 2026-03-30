# AIMHook — Privacy-Preserving Intent Matching for Uniswap v4

Privacy-preserving Coincidence of Wants (CoW) protocol built as a Uniswap v4 hook using **Fhenix Fully Homomorphic Encryption (FHE)**.

Swap amounts, minimum returns, and directions are encrypted end-to-end. Matching happens entirely on encrypted data via the CoFHE coprocessor — no one sees your order size, not even the contract.

## The Problem

- **$500M+ lost annually to MEV** in DeFi. Front-runners extract value from every visible swap.
- **15-40% of auction value** captured by MEV bots, with 75% of losses hitting trades under $20K.
- **Institutions can't use transparent rails.** Compliance won't allow visible positions and strategies on-chain.

Existing AMMs broadcast every swap intention in the mempool before execution. Privacy isn't a feature you bolt on later — it's architecture.

## How It Works

```
User submits swap ──► cofhejs/web encrypts amount + minReturn (client-side FHE)
                            │
                            ▼
              ┌─────────────────────────────┐
              │     AIMHook.beforeSwap()     │
              │                             │
              │  1. Validate encrypted input │
              │  2. Store encrypted intent   │
              │  3. Scan queue for match     │
              │     (FHE comparisons only)   │
              │  4. If matched → link pair   │
              │     If not → queue + AMM     │
              └─────────────────────────────┘
                            │
                    Match found?
                   ╱            ╲
                 Yes             No
                  │               │
                  ▼               ▼
          Keeper settles     Normal AMM swap
          P2P after FHE      proceeds via
          decryption          Uniswap v4
```

### Key Flow

1. **Encrypt** — User's swap amount and minimum return are encrypted client-side using `cofhejs/web` with the user's wallet
2. **Submit** — Encrypted intent is submitted as `hookData` in a Uniswap v4 swap call
3. **Match** — `beforeSwap` hook scans the intent queue using FHE operations (encrypted comparisons, no plaintext exposed)
4. **Settle** — Matched intents are settled P2P by a keeper bot after CoFHE async decryption completes
5. **Fallback** — Unmatched intents fall through to the normal Uniswap v4 AMM

## Deployed Contracts (Arbitrum Sepolia)

| Contract | Address |
|----------|---------|
| AIMHook | `0x055836DFf5fCff373110dDE7fe856259B9970088` |
| Token0 (TKA) | `0x6D228685fb8B30C9863C5d22cE6c59b56CDCb9D8` |
| Token1 (TKB) | `0xB48e7d0a39edAf931c470a5d97029099f133d358` |
| PoolManager (Uniswap v4) | `0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317` |
| PoolSwapTest | `0xf3A39C86dbd13C45365E57FB90fe413371F65AF8` |
| CoFHE TaskManager | `0xeA30c4B8b44078Bbf8a6ef5b9f1eC1626C7848D9` |

## Architecture

```
src/
├── AIMHook.sol          # Main hook — beforeSwap entry point, intent lifecycle
├── AIMStorage.sol       # Storage layout — intents, pools, decrypt tracking
├── AIMFHE.sol           # FHE utilities — encrypted constants, compatibility checks
├── AIMMatcher.sol       # Matching engine — scans queue with FHE comparisons
├── AIMSettlement.sol    # P2P settlement — resolves matched intents after decryption
├── FHEClientHelper.sol  # Client encryption helpers and validation
└── interfaces/
    └── IAIMHook.sol     # External interface

script/
├── DeployAll.s.sol      # Full deployment (tokens + hook + pool + liquidity)
├── Deploy.s.sol         # CREATE2 deployment with HookMiner
├── AddLiquidity.s.sol   # Liquidity provisioning
├── TestSwap.s.sol       # Test swap on live chain
├── EncryptIntent.ts     # CLI intent encryption via cofhejs
└── KeeperBot.ts         # Settlement bot — polls and settles matched intents

frontend/
├── app/
│   ├── providers.tsx       # Wagmi + RainbowKit + FhenixProvider
│   └── page.tsx            # Main UI
└── components/
    ├── SwapIntent.tsx      # Encrypted swap intent form
    ├── FhenixProvider.tsx  # Client-side CoFHE wrapper (cofhejs/web)
    ├── IntentHistory.tsx   # Intent status tracker
    ├── PermitManager.tsx   # FHE permit management
    └── WalletConnect.tsx   # Wallet connection

test/
├── AIMHook.t.sol          # Core hook tests — intent creation, matching, validation
├── AIMMatcher.t.sol       # Matching engine — scan limits, expiry, FIFO ordering
├── AIMSettlement.t.sol    # Settlement — token transfers, matched status checks
├── ForkSwap.t.sol         # Fork tests against live Arbitrum Sepolia
└── utils/
    ├── CoFheTestHelper.sol # Base test — deploys mock, provides helpers
    ├── MockTaskManager.sol # Full ITaskManager mock with plaintext FHE simulation
    └── HookMiner.sol       # CREATE2 salt mining for deterministic hook addresses
```

## Privacy Guarantees

| What | Visibility |
|------|-----------|
| Swap amount | Encrypted (euint128) — never visible on-chain |
| Minimum return | Encrypted (euint128) — never visible on-chain |
| Swap direction | Encrypted (ebool) — hidden until settlement |
| Match result | Computed on encrypted data via CoFHE coprocessor |
| Settlement amount | Revealed only after async decryption, only to participants |

The contract itself cannot read the plaintext values. All comparisons happen through FHE operations on the CoFHE coprocessor.

## FHE Integration

### Encrypted Operations Used

- `FHE.asEuint128(InEuint128)` — Verify and convert client-encrypted inputs
- `FHE.gt()`, `FHE.sub()`, `FHE.mul()`, `FHE.div()`, `FHE.lte()` — Encrypted arithmetic for compatibility checks
- `FHE.xor()` — Direction matching (opposite directions = match candidate)
- `FHE.select()` — Safe absolute difference (avoids underflow on encrypted values)
- `FHE.and()` — Combine match conditions
- `FHE.decrypt()` + `FHE.getDecryptResultSafe()` — Async decryption for settlement

### Permission Model

Every intermediate FHE result requires explicit permission grants:

```solidity
euint128 amount = FHE.asEuint128(encAmount);
FHE.allowThis(amount);      // Contract can use this value
FHE.allow(amount, owner);   // Owner can unseal their data
```

### Async Decryption

CoFHE decryption is asynchronous (takes multiple blocks):

```
beforeSwap() → FHE.decrypt(amount) → stores DecryptRequest
                                           │
                            ... N blocks pass ...
                                           │
Keeper calls settleMatchedIntents() → AIMFHE.pollDecryption()
                                           │
                                    CoFHE resolved? ──► Execute P2P transfer
```

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+
- Funded wallet on Arbitrum Sepolia

### Build & Test

```bash
forge install
forge build
forge test -vv
```

```
Ran 4 test suites: 17 tests passed, 0 failed, 0 skipped
```

### Deploy

```bash
cp .env.example .env
# Fill in your private key and RPC URL

# Deploy everything (tokens, hook, pool, liquidity)
forge script script/DeployAll.s.sol \
  --rpc-url $ARB_SEPOLIA_RPC \
  --broadcast
```

### Run Frontend

```bash
cd frontend
npm install
npm run dev
```

Visit `http://localhost:3000` — connect wallet, select Arbitrum Sepolia, initialize FHE session, submit encrypted swap intents.

## Tech Stack

- **Fhenix CoFHE** — Fully Homomorphic Encryption coprocessor for on-chain encrypted compute
- **cofhejs/web** — Client-side FHE SDK for browser-based encryption with user's wallet
- **Uniswap v4** — Hook architecture with `beforeSwap` + `beforeSwapReturnDelta`
- **Foundry** — Smart contract development, testing, deployment
- **Next.js 14** — Frontend with RainbowKit wallet integration
- **Arbitrum Sepolia** — Primary deployment chain (Chain ID: 421614)

## Buildathon

Built for the **Privacy-by-Design dApp Buildathon** by Fhenix.

## License

MIT
