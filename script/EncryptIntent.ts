/**
 * Client-side encryption script for AIMHook using cofhejs/node
 *
 * Migrated from deprecated fhenixjs to cofhejs (CoFHE SDK).
 * Uses server-side Node.js environment for reliable WASM loading.
 *
 * Usage:
 *   ARB_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc \
 *   PRIVATE_KEY=0x... \
 *   ts-node script/EncryptIntent.ts
 */

import { ethers } from 'ethers';

// Contract ABIs
const SWAP_TEST_ABI = [
  'function swap(tuple(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) key, tuple(bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96) params, tuple(bool takeClaims, bool settleUsingBurn) testSettings, bytes hookData) external payable returns (int256)'
];

/**
 * Encrypt swap parameters using cofhejs/node
 */
export async function encryptIntentData(
  amount: bigint,
  minReturn: bigint,
  provider: ethers.Provider,
  signer: ethers.Signer
): Promise<string> {
  // Dynamic import of cofhejs/node (WASM loads reliably in Node.js)
  const { cofhejs, Encryptable } = await import('cofhejs/node');

  // Initialize cofhejs with provider and signer
  await cofhejs.initialize({
    provider: provider as any,
    signer: signer as any,
  });

  // Create permit for encryption
  await cofhejs.createPermit();

  // Encrypt amounts
  const encryptedAmount = await cofhejs.encrypt(Encryptable.uint128(amount));
  const encryptedMinReturn = await cofhejs.encrypt(Encryptable.uint128(minReturn));

  console.log('Encrypted amount:', encryptedAmount);
  console.log('Encrypted minReturn:', encryptedMinReturn);

  // Encode as hookData (InEuint128, InEuint128)
  const hookData = ethers.AbiCoder.defaultAbiCoder().encode(
    [
      'tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature)',
      'tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature)'
    ],
    [
      [
        encryptedAmount.ctHash,
        encryptedAmount.securityZone,
        encryptedAmount.utype || 7, // euint128
        encryptedAmount.signature || '0x'
      ],
      [
        encryptedMinReturn.ctHash,
        encryptedMinReturn.securityZone,
        encryptedMinReturn.utype || 7,
        encryptedMinReturn.signature || '0x'
      ]
    ]
  );

  return hookData;
}

/**
 * Submit encrypted intent via SwapTest contract
 */
export async function submitEncryptedIntent(
  signer: ethers.Signer,
  swapTestAddress: string,
  poolKey: {
    currency0: string;
    currency1: string;
    fee: number;
    tickSpacing: number;
    hooks: string;
  },
  swapParams: {
    zeroForOne: boolean;
    amountSpecified: bigint;
    sqrtPriceLimitX96: bigint;
  },
  amount: bigint,
  minReturn: bigint
): Promise<ethers.ContractTransactionResponse> {
  const provider = signer.provider!;

  // Encrypt intent data
  const hookData = await encryptIntentData(amount, minReturn, provider, signer);

  // Connect to SwapTest contract
  const swapTest = new ethers.Contract(swapTestAddress, SWAP_TEST_ABI, signer);

  // Submit swap with encrypted hookData
  const tx = await swapTest.swap(
    poolKey,
    swapParams,
    { takeClaims: false, settleUsingBurn: false },
    hookData
  );

  console.log('Intent submitted! Tx:', tx.hash);
  return tx;
}

/**
 * Example usage
 */
async function example() {
  const rpcUrl = process.env.ARB_SEPOLIA_RPC || 'https://sepolia-rollup.arbitrum.io/rpc';
  const privateKey = process.env.PRIVATE_KEY;

  if (!privateKey) {
    console.error('Set PRIVATE_KEY environment variable');
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log('Wallet:', wallet.address);
  console.log('Chain:', (await provider.getNetwork()).chainId);

  const SWAP_TEST = process.env.SWAP_TEST || '';
  const AIM_HOOK = process.env.AIM_HOOK || '';
  const TOKEN0 = process.env.TOKEN0 || '';
  const TOKEN1 = process.env.TOKEN1 || '';

  if (!SWAP_TEST || !AIM_HOOK || !TOKEN0 || !TOKEN1) {
    console.error('Set SWAP_TEST, AIM_HOOK, TOKEN0, TOKEN1 environment variables');
    process.exit(1);
  }

  const poolKey = {
    currency0: TOKEN0,
    currency1: TOKEN1,
    fee: 3000,
    tickSpacing: 60,
    hooks: AIM_HOOK
  };

  // Swap: 1 ETH for min 1800 USDC with 0.5% slippage
  const amount = ethers.parseEther('1');
  const minReturn = ethers.parseUnits('1791', 6); // 1800 * 0.995

  const swapParams = {
    zeroForOne: true,
    amountSpecified: -amount,
    sqrtPriceLimitX96: 0n
  };

  const tx = await submitEncryptedIntent(
    wallet,
    SWAP_TEST,
    poolKey,
    swapParams,
    amount,
    minReturn
  );

  await tx.wait();
  console.log('Intent submitted and confirmed!');
}

// Run if executed directly
example().catch(console.error);
