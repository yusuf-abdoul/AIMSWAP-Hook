/**
 * Keeper Bot for AIMHook Settlement
 *
 * Monitors IntentMatched events and triggers settlement after FHE decryption.
 * Targets Arbitrum Sepolia (primary) or Ethereum Sepolia.
 *
 * Usage:
 *   ARB_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc \
 *   KEEPER_PRIVATE_KEY=0x... \
 *   AIM_HOOK_ADDRESS=0x... \
 *   ts-node script/KeeperBot.ts
 */

import { ethers } from 'ethers';

const AIM_HOOK_ABI = [
  'event IntentMatched(bytes32 indexed poolId, bytes32 indexed intentA, bytes32 indexed intentB)',
  'event IntentSettled(bytes32 indexed poolId, bytes32 indexed intentId, uint128 amountSettled)',
  'function settleMatchedIntents(bytes32 poolId, bytes32 intentAId, bytes32 intentBId) external',
  'function getIntent(bytes32 poolId, bytes32 intentId) external view returns (tuple(address owner, uint256 amount, uint256 minReturn, uint256 zeroForOne, uint32 createdBlock, uint32 expireBlock, uint8 status, bytes32 matchedWith))',
  'function getMatchedIntent(bytes32 poolId, bytes32 intentId) external view returns (bytes32)',
];

interface MatchedIntent {
  poolId: string;
  intentAId: string;
  intentBId: string;
  blockNumber: number;
  retries: number;
}

export class AIMKeeperBot {
  private hook: ethers.Contract;
  private signer: ethers.Signer;
  private pendingSettlements: Map<string, MatchedIntent> = new Map();
  private decryptionDelay: number;
  private maxRetries: number;
  private intervalId: ReturnType<typeof setInterval> | null = null;

  constructor(
    hookAddress: string,
    signer: ethers.Signer,
    decryptionDelay: number = 50,  // ~50 blocks for CoFHE decryption on Arb Sepolia
    maxRetries: number = 10
  ) {
    this.hook = new ethers.Contract(hookAddress, AIM_HOOK_ABI, signer);
    this.signer = signer;
    this.decryptionDelay = decryptionDelay;
    this.maxRetries = maxRetries;
  }

  async start() {
    const hookAddr = await this.hook.getAddress();
    const network = await this.signer.provider!.getNetwork();

    console.log('AIM Keeper Bot started');
    console.log(`  Hook: ${hookAddr}`);
    console.log(`  Chain: ${network.name} (${network.chainId})`);
    console.log(`  Decryption delay: ${this.decryptionDelay} blocks`);
    console.log(`  Max retries: ${this.maxRetries}\n`);

    // Listen for IntentMatched events
    this.hook.on('IntentMatched', async (poolId: string, intentA: string, intentB: string, event: any) => {
      const blockNumber = event.log?.blockNumber || await this.signer.provider!.getBlockNumber();
      await this.handleMatchedIntent(poolId, intentA, intentB, blockNumber);
    });

    // Poll for settlements every ~3 seconds (Arb Sepolia block time)
    this.intervalId = setInterval(() => this.processPendingSettlements(), 3000);
  }

  private async handleMatchedIntent(
    poolId: string,
    intentAId: string,
    intentBId: string,
    blockNumber: number
  ) {
    const matchKey = `${poolId}-${intentAId}-${intentBId}`;

    console.log(`\nMatch detected at block ${blockNumber}`);
    console.log(`  Pool: ${poolId.slice(0, 10)}...`);
    console.log(`  Intent A: ${intentAId.slice(0, 10)}...`);
    console.log(`  Intent B: ${intentBId.slice(0, 10)}...`);

    this.pendingSettlements.set(matchKey, {
      poolId,
      intentAId,
      intentBId,
      blockNumber,
      retries: 0,
    });

    console.log(`  Waiting ${this.decryptionDelay} blocks for FHE decryption...`);
  }

  private async processPendingSettlements() {
    const provider = this.signer.provider!;
    const currentBlock = await provider.getBlockNumber();

    for (const [matchKey, match] of this.pendingSettlements.entries()) {
      const blocksElapsed = currentBlock - match.blockNumber;

      if (blocksElapsed < this.decryptionDelay) continue;

      console.log(`\nSettlement attempt for match at block ${match.blockNumber} (${blocksElapsed} blocks elapsed)`);

      try {
        const gasEstimate = await this.hook.settleMatchedIntents.estimateGas(
          match.poolId,
          match.intentAId,
          match.intentBId
        );

        const tx = await this.hook.settleMatchedIntents(
          match.poolId,
          match.intentAId,
          match.intentBId,
          { gasLimit: gasEstimate * 12n / 10n }
        );

        console.log(`  Tx: ${tx.hash}`);
        const receipt = await tx.wait();
        console.log(`  Settled! Gas: ${receipt.gasUsed}`);

        this.pendingSettlements.delete(matchKey);
      } catch (error: any) {
        match.retries++;
        const msg = error.message || '';

        if (msg.includes('IntentsNotMatched')) {
          console.log('  Already settled or not matched, removing.');
          this.pendingSettlements.delete(matchKey);
        } else if (msg.includes('not decrypted') || msg.includes('DecryptionNotReady')) {
          console.log(`  Decryption pending, retry ${match.retries}/${this.maxRetries}`);
          if (match.retries >= this.maxRetries) {
            console.log('  Max retries reached, removing.');
            this.pendingSettlements.delete(matchKey);
          }
        } else {
          console.error(`  Error: ${msg.slice(0, 100)}`);
          if (match.retries >= this.maxRetries) {
            this.pendingSettlements.delete(matchKey);
          }
        }
      }
    }
  }

  stop() {
    this.hook.removeAllListeners();
    if (this.intervalId) clearInterval(this.intervalId);
    console.log('\nKeeper bot stopped');
  }

  getPendingCount(): number {
    return this.pendingSettlements.size;
  }
}

// ─── Main ───

async function main() {
  const RPC_URL = process.env.ARB_SEPOLIA_RPC || process.env.ETH_SEPOLIA_RPC || 'https://sepolia-rollup.arbitrum.io/rpc';
  const PRIVATE_KEY = process.env.KEEPER_PRIVATE_KEY || '';
  const HOOK_ADDRESS = process.env.AIM_HOOK_ADDRESS || '';

  if (!PRIVATE_KEY || !HOOK_ADDRESS) {
    console.error('Missing environment variables:');
    console.error('  KEEPER_PRIVATE_KEY - Private key for keeper wallet');
    console.error('  AIM_HOOK_ADDRESS   - AIMHook contract address');
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  console.log(`Keeper wallet: ${wallet.address}`);
  const balance = await provider.getBalance(wallet.address);
  console.log(`Balance: ${ethers.formatEther(balance)} ETH`);

  const keeper = new AIMKeeperBot(HOOK_ADDRESS, wallet);
  await keeper.start();

  process.on('SIGINT', () => {
    keeper.stop();
    process.exit(0);
  });

  console.log('\nKeeper bot running. Press Ctrl+C to stop.\n');
}

export default AIMKeeperBot;

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
