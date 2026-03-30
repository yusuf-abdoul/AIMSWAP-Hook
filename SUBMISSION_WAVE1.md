# AIMHook — Privacy-Preserving Intent Matching for Uniswap v4

## Wave 1: Ideation Submission

---

## One-Liner

A Uniswap v4 hook that matches swap intents peer-to-peer using Fhenix FHE — amounts, directions, and order sizes stay encrypted throughout the entire lifecycle.

---

## Problem

DeFi loses over $500M annually to MEV extraction. Every swap submitted to a transparent AMM broadcasts its size and direction to the mempool before execution. Front-runners, sandwich bots, and arbitrageurs extract value from this information asymmetry.

This isn't just a retail problem. Institutions evaluating on-chain execution can't deploy strategies on transparent rails — compliance won't allow visible positions. Traders protecting alpha can't use pools where their order flow is public.

The root cause is architectural: AMMs were built for transparency. Privacy needs to be in the foundation, not patched on after the fact.

---

## Solution: AIMHook

AIMHook is a Uniswap v4 `beforeSwap` hook that intercepts swaps and routes them through an encrypted Coincidence of Wants (CoW) matching engine before they reach the AMM.

### How it works:

1. **User encrypts** their swap amount and minimum return using Fhenix CoFHE (via `cofhejs/node` server-side SDK)
2. **Hook receives** the encrypted intent in `beforeSwap` hookData
3. **Matching engine scans** the intent queue using only FHE operations — encrypted comparisons, encrypted arithmetic, no plaintext exposed at any point
4. **If matched**: Both intents are linked. A keeper bot settles P2P after CoFHE async decryption completes
5. **If unmatched**: The swap falls through to the normal Uniswap v4 AMM — no user friction

### What stays encrypted:

| Data | Type | Visibility |
|------|------|-----------|
| Swap amount | `euint128` | Never visible on-chain |
| Minimum return | `euint128` | Never visible on-chain |
| Swap direction | `ebool` | Hidden until settlement |
| Match compatibility | `ebool` | Computed entirely on encrypted data |

The contract cannot read plaintext values. The CoFHE coprocessor performs all comparisons on ciphertext.

---

## Why Fhenix / CoFHE

This project is only possible with FHE. Other privacy approaches don't fit:

- **ZK proofs** can prove properties about hidden data, but can't compute on it. We need encrypted arithmetic (is amount A within 5% of amount B?) that ZK can't do.
- **TEEs** require trust in hardware. CoFHE is cryptographic — no trusted hardware assumption.
- **Mixers/tumblers** hide identity, not transaction logic. We need the smart contract to operate on encrypted state.

Fhenix CoFHE gives us:
- `euint128` encrypted types for amounts
- `FHE.gt()`, `FHE.sub()`, `FHE.mul()`, `FHE.select()` for encrypted matching logic
- `FHE.allowThis()` / `FHE.allow()` permission model for access control
- Async decryption via `FHE.decrypt()` + keeper polling pattern
- Deployed and functional on Arbitrum Sepolia

---

## Architecture

```
┌──────────────┐     hookData (encrypted)     ┌─────────────────┐
│   Frontend   │ ────────────────────────────► │   AIMHook.sol   │
│  cofhejs API │                               │  beforeSwap()   │
└──────────────┘                               └────────┬────────┘
                                                        │
                                               ┌────────▼────────┐
                                               │  AIMMatcher.sol  │
                                               │  FHE scan queue  │
                                               └────────┬────────┘
                                                        │
                                              Match? ───┤
                                             ╱          │
                                           Yes          No
                                            │           │
                                   ┌────────▼──┐  ┌─────▼───────┐
                                   │  Matched   │  │  Queue for  │
                                   │  (keeper   │  │  future +   │
                                   │  settles)  │  │  AMM swap   │
                                   └────────────┘  └─────────────┘
```

### Contract modules:
- **AIMHook.sol** — Main hook, intent lifecycle, `beforeSwap` entry point
- **AIMFHE.sol** — Encrypted constants, compatibility checks with full `FHE.allowThis()` permissions
- **AIMMatcher.sol** — Queue scanning with FHE comparisons (direction XOR, amount tolerance)
- **AIMSettlement.sol** — P2P settlement after async decryption resolves
- **AIMStorage.sol** — Diamond-style storage with encrypted intent structs and decrypt tracking

### Frontend:
- Next.js with server-side API route (`/api/fhe`) using `cofhejs/node`
- No browser WASM — all encryption happens server-side for reliability
- RainbowKit + wagmi for wallet connection on Arbitrum Sepolia

### Keeper bot:
- Polls for matched intents
- Checks CoFHE decryption status
- Triggers `settleMatchedIntents()` when decryption resolves

---

## Current Status

| Component | Status |
|-----------|--------|
| Smart contracts (6 modules) | Complete, compiles |
| FHE integration (CoFHE permissions, async decrypt) | Complete |
| Test suite (14 tests) | All passing |
| Deploy scripts (CREATE2 + HookMiner) | Ready for Arb Sepolia |
| Frontend (Next.js + server-side CoFHE) | Built |
| Keeper bot | Script ready |

This is not a concept sketch — the core protocol is implemented and tested. Wave 1 is ideation, but we're already building.

---

## Application Area

**Confidential DeFi** — Private positions, MEV-protected execution, sealed-bid matching.

Directly addresses the buildathon's core thesis: protocols that build privacy into their architecture will outcompete those retrofitting it later.

---

## What We're Building Next (Waves 2-5)

### Wave 2: Testnet Deployment
- Deploy to Arbitrum Sepolia with live CoFHE coprocessor
- End-to-end encrypted swap flow (frontend → encrypt → hook → match → settle)
- Contract verification on Arbiscan

### Wave 3: Protocol Hardening
- Multi-pool support with cross-pool intent matching
- Partial fill handling with encrypted remainder tracking
- Gas optimization for FHE operations (batch decrypt, cached constants)
- Keeper incentive mechanism

### Wave 4: Advanced Features
- Time-weighted encrypted order books
- Limit order intents (encrypted price thresholds)
- Integration with Privara for confidential payment settlement rails

### Wave 5: Production Readiness
- Security audit preparation
- Mainnet deployment strategy
- SDK for third-party integrations
- Documentation and developer guides

---

## Team

Building at the intersection of DeFi infrastructure and confidential compute. Deep experience with Uniswap v4 hook architecture and Solidity development.

---

## Links

- **Repository**: [GitHub — AIMHook](https://github.com/) *(update with your repo URL)*
- **Target chain**: Arbitrum Sepolia (Chain ID: 421614)
- **Fhenix docs**: https://docs.fhenix.io
- **Uniswap v4 hooks**: https://docs.uniswap.org/contracts/v4/overview
