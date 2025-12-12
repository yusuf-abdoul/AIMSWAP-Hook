/**
 * Keeper Bot for AIMHook Settlement
 * Monitors IntentMatched events and triggers settlement after FHE decryption
 */

import { ethers } from 'ethers';

const AIM_HOOK_ABI = [
  'event IntentMatched(bytes32 indexed poolId, bytes32 indexed intentA, bytes32 indexed intentB, uint128 amountMatched)',
  'function settleMatchedIntents(bytes32 poolId, bytes32 intentAId, bytes32 intentBId) external',
  'function ownerNonces(address owner) external view returns (uint256)'
];

interface MatchedIntent {
  poolId: string;
  intentAId: string;
  intentBId: string;
  blockNumber: number;
}

/**
 * Keeper Bot Class
 */
export class AIMKeeperBot {
  private hook: ethers.Contract;
  private signer: ethers.Signer;
  private pendingSettlements: Map<string, MatchedIntent> = new Map();
  private decryptionDelay: number; // blocks to wait for FHE decryption

  constructor(
    hookAddress: string,
    signer: ethers.Signer,
    decryptionDelay: number = 10 // ~10 blocks for FHE decryption
  ) {
    this.hook = new ethers.Contract(hookAddress, AIM_HOOK_ABI, signer);
    this.signer = signer;
    this.decryptionDelay = decryptionDelay;
  }

  /**
   * Start monitoring for matched intents
   */
  async start() {
    console.log('🤖 AIM Keeper Bot started');
    console.log(`📡 Monitoring hook: ${await this.hook.getAddress()}`);
    console.log(`⏱️  Decryption delay: ${this.decryptionDelay} blocks\n`);

    // Listen for IntentMatched events
    this.hook.on('IntentMatched', async (poolId, intentA, intentB, amountMatched, event) => {
      await this.handleMatchedIntent(poolId, intentA, intentB, event.log.blockNumber);
    });

    // Periodically check for settlements ready to execute
    setInterval(() => this.processPendingSettlements(), 12000); // Every ~12 seconds (1 block)
  }

  /**
   * Handle new matched intent event
   */
  private async handleMatchedIntent(
    poolId: string,
    intentAId: string,
    intentBId: string,
    blockNumber: number
  ) {
    const matchKey = `${poolId}-${intentAId}-${intentBId}`;

    console.log(`\n✅ New match detected at block ${blockNumber}`);
    console.log(`   Pool ID: ${poolId}`);
    console.log(`   Intent A: ${intentAId}`);
    console.log(`   Intent B: ${intentBId}`);

    // Store for delayed settlement
    this.pendingSettlements.set(matchKey, {
      poolId,
      intentAId,
      intentBId,
      blockNumber
    });

    console.log(`⏳ Waiting ${this.decryptionDelay} blocks for FHE decryption...`);
  }

  /**
   * Process settlements that are ready (decryption completed)
   */
  private async processPendingSettlements() {
    const provider = this.signer.provider!;
    const currentBlock = await provider.getBlockNumber();

    for (const [matchKey, match] of this.pendingSettlements.entries()) {
      const blocksElapsed = currentBlock - match.blockNumber;

      // Check if enough blocks have passed for decryption
      if (blocksElapsed >= this.decryptionDelay) {
        console.log(`\n🔓 Decryption complete for match at block ${match.blockNumber}`);
        console.log(`   Blocks elapsed: ${blocksElapsed}`);

        try {
          await this.settleMatch(match);
          this.pendingSettlements.delete(matchKey);
        } catch (error) {
          console.error(`❌ Settlement failed:`, error);
          // Keep in queue to retry next iteration
        }
      }
    }
  }

  /**
   * Execute settlement transaction
   */
  private async settleMatch(match: MatchedIntent) {
    console.log(`\n💰 Settling matched intents...`);
    console.log(`   Pool: ${match.poolId}`);
    console.log(`   Intent A: ${match.intentAId}`);
    console.log(`   Intent B: ${match.intentBId}`);

    try {
      // Estimate gas
      const gasEstimate = await this.hook.settleMatchedIntents.estimateGas(
        match.poolId,
        match.intentAId,
        match.intentBId
      );

      console.log(`   Estimated gas: ${gasEstimate.toString()}`);

      // Execute settlement
      const tx = await this.hook.settleMatchedIntents(
        match.poolId,
        match.intentAId,
        match.intentBId,
        {
          gasLimit: gasEstimate * 12n / 10n // 20% buffer
        }
      );

      console.log(`   Transaction submitted: ${tx.hash}`);

      const receipt = await tx.wait();

      console.log(`✅ Settlement successful!`);
      console.log(`   Gas used: ${receipt.gasUsed.toString()}`);
      console.log(`   Block: ${receipt.blockNumber}`);

    } catch (error: any) {
      // Check if already settled
      if (error.message?.includes('Intents not matched')) {
        console.log(`⚠️  Intents already settled or not matched`);
      } else if (error.message?.includes('Amounts not decrypted yet')) {
        console.log(`⏳ FHE decryption still pending, will retry...`);
        throw error; // Keep in queue
      } else {
        console.error(`❌ Settlement error:`, error.message);
        throw error;
      }
    }
  }

  /**
   * Stop the keeper bot
   */
  stop() {
    this.hook.removeAllListeners();
    console.log('\n🛑 Keeper bot stopped');
  }

  /**
   * Get current pending settlements count
   */
  getPendingCount(): number {
    return this.pendingSettlements.size;
  }
}

/**
 * Example usage
 */
async function main() {
  // Configuration
  const RPC_URL = process.env.RPC_URL || 'https://fhenix-testnet-rpc-url';
  const PRIVATE_KEY = process.env.KEEPER_PRIVATE_KEY || '';
  const HOOK_ADDRESS = process.env.AIM_HOOK_ADDRESS || '';

  if (!PRIVATE_KEY || !HOOK_ADDRESS) {
    console.error('❌ Missing environment variables:');
    console.error('   KEEPER_PRIVATE_KEY - Private key for keeper wallet');
    console.error('   AIM_HOOK_ADDRESS - AIMHook contract address');
    process.exit(1);
  }

  // Setup provider and signer
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  console.log(`\n🔑 Keeper wallet: ${wallet.address}`);
  const balance = await provider.getBalance(wallet.address);
  console.log(`💰 Balance: ${ethers.formatEther(balance)} ETH`);

  // Start keeper bot
  const keeper = new AIMKeeperBot(HOOK_ADDRESS, wallet);
  await keeper.start();

  // Graceful shutdown
  process.on('SIGINT', () => {
    console.log('\n\n🛑 Shutting down keeper bot...');
    keeper.stop();
    process.exit(0);
  });

  // Keep alive
  console.log('\n✅ Keeper bot running. Press Ctrl+C to stop.\n');
}

export default AIMKeeperBot;

// Run if executed directly (ES module compatible)
main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
