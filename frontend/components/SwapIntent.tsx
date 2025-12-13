'use client';

import { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import { useAccount, useWalletClient, usePublicClient } from 'wagmi';
import { useFhenix } from './FhenixProvider';

// ERC20 ABI for approve and allowance
const ERC20_ABI = [
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' }
    ],
    outputs: [{ type: 'bool' }]
  },
  {
    name: 'allowance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' }
    ],
    outputs: [{ type: 'uint256' }]
  },
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'account', type: 'address' }
    ],
    outputs: [{ type: 'uint256' }]
  },
  {
    name: 'symbol',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'string' }]
  },
  {
    name: 'decimals',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint8' }]
  }
] as const;

/**
 * SwapIntent Component - Testing fhenixjs@0.4.2-alpha.2
 * Allows users to create encrypted swap intents for AIMHook
 */
export default function SwapIntent() {
  const { address } = useAccount();
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();
  const { cofheClient, isLoading: fheLoading, error: fheError } = useFhenix();

  const [inputAmount, setInputAmount] = useState('');
  const [slippage, setSlippage] = useState('0.5'); // Default 0.5% slippage
  const [zeroForOne, setZeroForOne] = useState(true);
  const [loading, setLoading] = useState(false);
  const [encrypting, setEncrypting] = useState(false);
  const [approving, setApproving] = useState(false);
  const [txHash, setTxHash] = useState('');
  const [allowance, setAllowance] = useState<bigint>(0n);
  const [tokenSymbol, setTokenSymbol] = useState<string>('');
  const [useFHE, setUseFHE] = useState(false); // Disable FHE by default for demo

  // User-configurable token addresses
  const [token0Input, setToken0Input] = useState(process.env.NEXT_PUBLIC_TOKEN0 || '');
  const [token1Input, setToken1Input] = useState(process.env.NEXT_PUBLIC_TOKEN1 || '');
  const [token0Symbol, setToken0Symbol] = useState('Token0');
  const [token1Symbol, setToken1Symbol] = useState('Token1');
  const [token0Balance, setToken0Balance] = useState<string>('0');
  const [token1Balance, setToken1Balance] = useState<string>('0');
  const [token0Decimals, setToken0Decimals] = useState<number>(18);
  const [token1Decimals, setToken1Decimals] = useState<number>(18);

  // Contract addresses
  const SWAP_TEST = process.env.NEXT_PUBLIC_SWAP_TEST || '';
  const AIM_HOOK = process.env.NEXT_PUBLIC_AIM_HOOK || '';

  // Use user input or fallback to env
  const TOKEN0 = token0Input;
  const TOKEN1 = token1Input;

  // Get the token we're selling based on direction
  const getInputToken = () => (zeroForOne ? TOKEN0 : TOKEN1);

  // Fetch token info when addresses change
  useEffect(() => {
    const fetchTokenInfo = async () => {
      if (!publicClient || !address) return;

      try {
        if (TOKEN0 && ethers.isAddress(TOKEN0)) {
          const [symbol0, balance0, decimals0] = await Promise.all([
            publicClient.readContract({
              address: TOKEN0 as `0x${string}`,
              abi: ERC20_ABI,
              functionName: 'symbol'
            } as any),
            publicClient.readContract({
              address: TOKEN0 as `0x${string}`,
              abi: ERC20_ABI,
              functionName: 'balanceOf',
              args: [address]
            } as any),
            publicClient.readContract({
              address: TOKEN0 as `0x${string}`,
              abi: ERC20_ABI,
              functionName: 'decimals'
            } as any)
          ]);
          setToken0Symbol(symbol0 as string);
          setToken0Decimals(decimals0 as number);
          setToken0Balance(ethers.formatUnits(balance0 as bigint, decimals0 as number));
        }

        if (TOKEN1 && ethers.isAddress(TOKEN1)) {
          const [symbol1, balance1, decimals1] = await Promise.all([
            publicClient.readContract({
              address: TOKEN1 as `0x${string}`,
              abi: ERC20_ABI,
              functionName: 'symbol'
            } as any),
            publicClient.readContract({
              address: TOKEN1 as `0x${string}`,
              abi: ERC20_ABI,
              functionName: 'balanceOf',
              args: [address]
            } as any),
            publicClient.readContract({
              address: TOKEN1 as `0x${string}`,
              abi: ERC20_ABI,
              functionName: 'decimals'
            } as any)
          ]);
          setToken1Symbol(symbol1 as string);
          setToken1Decimals(decimals1 as number);
          setToken1Balance(ethers.formatUnits(balance1 as bigint, decimals1 as number));
        }
      } catch (error) {
        console.error('Error fetching token info:', error);
      }
    };

    fetchTokenInfo();
  }, [TOKEN0, TOKEN1, publicClient, address]);

  // Check allowance when component loads or direction changes
  useEffect(() => {
    const checkAllowance = async () => {
      if (!address || !walletClient || !publicClient || !SWAP_TEST) return;

      try {
        const inputToken = getInputToken();
        if (!inputToken || !ethers.isAddress(inputToken)) return;

        // Use publicClient for read operations
        const currentAllowance = await publicClient.readContract({
          address: inputToken as `0x${string}`,
          abi: ERC20_ABI,
          functionName: 'allowance',
          args: [address, SWAP_TEST as `0x${string}`]
        } as any);

        const symbol = await publicClient.readContract({
          address: inputToken as `0x${string}`,
          abi: ERC20_ABI,
          functionName: 'symbol'
        } as any);

        setAllowance(currentAllowance as bigint);
        setTokenSymbol(symbol as string);
      } catch (error) {
        console.error('Error checking allowance:', error);
      }
    };

    checkAllowance();
  }, [address, walletClient, publicClient, SWAP_TEST, zeroForOne, TOKEN0, TOKEN1]);

  // Handle token approval
  const handleApprove = async () => {
    if (!walletClient || !address || !publicClient) {
      alert('Please connect wallet');
      return;
    }

    try {
      setApproving(true);
      const inputToken = getInputToken();

      console.log('Approving SwapTest to spend tokens...');

      const hash = await walletClient.writeContract({
        address: inputToken as `0x${string}`,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [SWAP_TEST as `0x${string}`, ethers.MaxUint256]
      });

      console.log('Approval transaction submitted:', hash);
      await publicClient.waitForTransactionReceipt({ hash });

      // Refresh allowance
      const newAllowance = await publicClient.readContract({
        address: inputToken as `0x${string}`,
        abi: ERC20_ABI,
        functionName: 'allowance',
        args: [address, SWAP_TEST as `0x${string}`]
      } as any);

      setAllowance(newAllowance as bigint);

      alert('Tokens approved successfully!');
    } catch (error: any) {
      console.error('Error approving tokens:', error);
      alert(`Approval failed: ${error.message}`);
    } finally {
      setApproving(false);
    }
  };

  // Check if user has sufficient allowance
  const hasAllowance = () => {
    if (!inputAmount) return true;
    try {
      const decimals = zeroForOne ? token0Decimals : token1Decimals;
      const amountWei = ethers.parseUnits(inputAmount, decimals);
      return allowance >= amountWei;
    } catch {
      return false;
    }
  };

  const handleSubmitIntent = async () => {
    if (!walletClient || !address || !publicClient) {
      alert('Please connect wallet');
      return;
    }

    if (useFHE && !cofheClient) {
      alert('CoFHE client not initialized. Please wait...');
      return;
    }

    if (!inputAmount) {
      alert('Please enter amount');
      return;
    }

    try {
      setLoading(true);

      // Get correct decimals for input token
      const inputDecimals = zeroForOne ? token0Decimals : token1Decimals;

      // Convert amounts using correct decimals
      const amountWei = ethers.parseUnits(inputAmount, inputDecimals);

      // Calculate minimum return with slippage
      // For demo: assume 1:1 price ratio, apply slippage
      const slippagePercent = parseFloat(slippage);
      const minReturnWei = (amountWei * BigInt(Math.floor((100 - slippagePercent) * 100))) / 10000n;

      let hookData: `0x${string}`;

      if (useFHE && cofheClient) {
        // Encrypt amounts using CoFHE
        setEncrypting(true);
        console.log('Encrypting amounts with cofhejs...');
        console.log('Amount:', amountWei.toString());
        console.log('Min return:', minReturnWei.toString());

        const { cofhejs, Encryptable } = cofheClient;

        try {
          // Use cofhejs encryption (returns InEuint128 format directly)
          const encryptedAmount = await cofhejs.encrypt(Encryptable.uint128(amountWei));
          const encryptedMinReturn = await cofhejs.encrypt(Encryptable.uint128(minReturnWei));

          console.log('Encrypted amount:', encryptedAmount);
          console.log('Encrypted minReturn:', encryptedMinReturn);

          // Verify encrypted values
          if (!encryptedAmount || !encryptedMinReturn) {
            throw new Error('Encryption returned null values');
          }

          setEncrypting(false);

          // cofhejs returns the correct InEuint128 format
          hookData = ethers.AbiCoder.defaultAbiCoder().encode(
            [
              'tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature)',
              'tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature)'
            ],
            [
              [
                encryptedAmount.ctHash || 0,
                encryptedAmount.securityZone || 0,
                encryptedAmount.utype || 7,
                encryptedAmount.signature || '0x'
              ],
              [
                encryptedMinReturn.ctHash || 0,
                encryptedMinReturn.securityZone || 0,
                encryptedMinReturn.utype || 7,
                encryptedMinReturn.signature || '0x'
              ]
            ]
          ) as `0x${string}`;
        } catch (encryptError: any) {
          setEncrypting(false);
          throw new Error(`Encryption failed: ${encryptError.message}`);
        }
      } else {
        // Demo mode: encode in InEuint128 format with dummy values
        console.log('Demo mode: Using plain values in encrypted format');
        hookData = ethers.AbiCoder.defaultAbiCoder().encode(
          [
            'tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature)',
            'tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature)'
          ],
          [
            [
              amountWei,      // Use amount as ctHash (demo only)
              0,              // securityZone
              7,              // utype for euint128
              '0x'            // empty signature
            ],
            [
              minReturnWei,   // Use minReturn as ctHash (demo only)
              0,              // securityZone
              7,              // utype for euint128
              '0x'            // empty signature
            ]
          ]
        ) as `0x${string}`;
      }

      // Pool key configuration
      const poolKey = {
        currency0: TOKEN0 as `0x${string}`,
        currency1: TOKEN1 as `0x${string}`,
        fee: 3000,
        tickSpacing: 60,
        hooks: AIM_HOOK as `0x${string}`
      };

      // Swap params
      const swapParams = {
        zeroForOne: zeroForOne,
        amountSpecified: -amountWei,
        sqrtPriceLimitX96: zeroForOne ? 0n : ethers.MaxUint256
      };

      // Submit transaction via SwapTest contract (recommended for testing)
      console.log('Submitting swap intent via PoolSwapTest...');
      const hash = await walletClient.writeContract({
        address: SWAP_TEST as `0x${string}`,
        abi: [
          {
            name: 'swap',
            type: 'function',
            stateMutability: 'payable',
            inputs: [
              {
                name: 'key',
                type: 'tuple',
                components: [
                  { name: 'currency0', type: 'address' },
                  { name: 'currency1', type: 'address' },
                  { name: 'fee', type: 'uint24' },
                  { name: 'tickSpacing', type: 'int24' },
                  { name: 'hooks', type: 'address' }
                ]
              },
              {
                name: 'params',
                type: 'tuple',
                components: [
                  { name: 'zeroForOne', type: 'bool' },
                  { name: 'amountSpecified', type: 'int256' },
                  { name: 'sqrtPriceLimitX96', type: 'uint160' }
                ]
              },
              {
                name: 'testSettings',
                type: 'tuple',
                components: [
                  { name: 'takeClaims', type: 'bool' },
                  { name: 'settleUsingBurn', type: 'bool' }
                ]
              },
              { name: 'hookData', type: 'bytes' }
            ],
            outputs: [{ type: 'int256' }]
          }
        ],
        functionName: 'swap',
        args: [
          poolKey,
          swapParams,
          { takeClaims: false, settleUsingBurn: false },
          hookData as `0x${string}`
        ],
        gas: 5000000n
      });

      console.log('Transaction submitted:', hash);
      setTxHash(hash);

      // Wait for confirmation
      await publicClient.waitForTransactionReceipt({ hash });

      alert('Intent submitted successfully!');
      setInputAmount('');

    } catch (error: any) {
      console.error('Error submitting intent:', error);

      // Better error messages
      let errorMsg = error.message || 'Unknown error';

      if (errorMsg.includes('PoolNotInitialized') || errorMsg.includes('not initialized')) {
        errorMsg = 'Pool not initialized. You need to initialize a pool with these tokens first.';
      } else if (errorMsg.includes('insufficient') || errorMsg.includes('balance')) {
        errorMsg = 'Insufficient token balance. Make sure you have enough tokens.';
      } else if (errorMsg.includes('allowance')) {
        errorMsg = 'Token allowance issue. Try approving again.';
      } else if (errorMsg.includes('reverted')) {
        errorMsg = `Transaction reverted. This pool may not exist or have liquidity.\n\nSteps to fix:\n1. Deploy tokens on Sepolia\n2. Initialize a pool via PoolManager\n3. Add liquidity to the pool\n4. Then try swapping`;
      }

      alert(`Swap failed: ${errorMsg}`);
    } finally {
      setLoading(false);
      setEncrypting(false);
    }
  };

  return (
    <div className="max-w-md mx-auto p-6 bg-white rounded-lg shadow-lg">
      <h2 className="text-2xl font-bold mb-6 text-gray-800">
        Create Private Swap Intent
      </h2>

      {/* Token Selection */}
      <div className="mb-4 p-4 bg-blue-50 border border-blue-200 rounded">
        <p className="text-sm font-semibold text-blue-900 mb-3">Select Token Pair</p>

        <div className="space-y-3">
          <div>
            <label className="block text-xs font-medium text-blue-900 mb-1">
              Token0 Address
            </label>
            <input
              type="text"
              value={token0Input}
              onChange={(e) => setToken0Input(e.target.value)}
              placeholder="0x..."
              className="w-full px-3 py-2 text-sm border border-blue-300 rounded focus:ring-2 focus:ring-blue-500 focus:border-transparent font-mono"
            />
            {token0Symbol && (
              <p className="text-xs text-blue-700 mt-1">
                {token0Symbol} • Balance: {parseFloat(token0Balance).toFixed(4)}
              </p>
            )}
          </div>

          <div>
            <label className="block text-xs font-medium text-blue-900 mb-1">
              Token1 Address
            </label>
            <input
              type="text"
              value={token1Input}
              onChange={(e) => setToken1Input(e.target.value)}
              placeholder="0x..."
              className="w-full px-3 py-2 text-sm border border-blue-300 rounded focus:ring-2 focus:ring-blue-500 focus:border-transparent font-mono"
            />
            {token1Symbol && (
              <p className="text-xs text-blue-700 mt-1">
                {token1Symbol} • Balance: {parseFloat(token1Balance).toFixed(4)}
              </p>
            )}
          </div>
        </div>

        <p className="text-xs text-blue-600 mt-3">
          💡 Enter any ERC20 token addresses. If a Uniswap v4 pool exists with these tokens, you can swap!
        </p>
      </div>

      {/* Demo Mode Toggle */}
      <div className="mb-4 p-4 bg-yellow-50 border border-yellow-200 rounded">
        <div className="flex items-center justify-between mb-2">
          <p className="text-sm font-semibold text-yellow-900">
            Demo Mode (FHE Disabled)
          </p>
          <label className="flex items-center space-x-2 cursor-pointer">
            <input
              type="checkbox"
              checked={useFHE}
              onChange={(e) => setUseFHE(e.target.checked)}
              className="rounded"
            />
            <span className="text-xs text-yellow-700">Enable FHE (experimental)</span>
          </label>
        </div>
        <p className="text-xs text-yellow-700">
          {useFHE ? (
            fheLoading ? (
              'Loading CoFHE client...'
            ) : fheError ? (
              `CoFHE Error: ${fheError}`
            ) : cofheClient ? (
              '✓ CoFHE client ready (Fhenix CoProcessor)'
            ) : (
              'Initializing CoFHE encryption...'
            )
          ) : (
            'Using plain values for demo - encryption disabled'
          )}
        </p>
      </div>

      {/* Swap Direction */}
      <div className="mb-4">
        <label className="block text-sm font-medium text-gray-700 mb-2">
          Swap Direction
        </label>
        <div className="flex space-x-4">
          <button
            onClick={() => setZeroForOne(true)}
            className={`flex-1 px-4 py-2 rounded transition-colors ${
              zeroForOne
                ? 'bg-blue-600 text-white'
                : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
            }`}
          >
            {token0Symbol} → {token1Symbol}
          </button>
          <button
            onClick={() => setZeroForOne(false)}
            className={`flex-1 px-4 py-2 rounded transition-colors ${
              !zeroForOne
                ? 'bg-blue-600 text-white'
                : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
            }`}
          >
            {token1Symbol} → {token0Symbol}
          </button>
        </div>
      </div>

      {/* Input Amount */}
      <div className="mb-4">
        <label className="block text-sm font-medium text-gray-700 mb-2">
          Amount to Swap
        </label>
        <input
          type="number"
          value={inputAmount}
          onChange={(e) => {
            const value = e.target.value;
            // Only allow positive numbers
            if (value === '' || parseFloat(value) >= 0) {
              setInputAmount(value);
            }
          }}
          placeholder="0.0"
          min="0"
          step="0.01"
          className="w-full px-4 py-2 border border-gray-300 rounded focus:ring-2 focus:ring-blue-500 focus:border-transparent"
        />
        <p className="mt-1 text-xs text-gray-500">
          {tokenSymbol || 'Token'} amount to swap
        </p>
      </div>

      {/* Slippage Tolerance */}
      <div className="mb-6">
        <label className="block text-sm font-medium text-gray-700 mb-2">
          Slippage Tolerance
        </label>
        <div className="flex space-x-2">
          {['0.1', '0.5', '1.0', '2.0'].map((s) => (
            <button
              key={s}
              onClick={() => setSlippage(s)}
              className={`flex-1 px-3 py-2 text-sm rounded transition-colors ${
                slippage === s
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              {s}%
            </button>
          ))}
        </div>
        <p className="mt-2 text-xs text-gray-500">
          Min return: {inputAmount ? (parseFloat(inputAmount) * (1 - parseFloat(slippage) / 100)).toFixed(4) : '0'} tokens
        </p>
      </div>

      {/* Encrypting Animation */}
      {encrypting && (
        <div className="mb-4 p-4 bg-blue-50 border border-blue-200 rounded animate-pulse">
          <div className="flex items-center space-x-3">
            <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-blue-600"></div>
            <p className="text-sm font-medium text-blue-900">
              Encrypting with FHE...
            </p>
          </div>
        </div>
      )}

      {/* Info Box */}
      <div className="mb-6 p-4 bg-blue-50 border border-blue-200 rounded">
        <h3 className="text-sm font-semibold text-blue-900 mb-2">
          🔒 Privacy-Preserving Swap
        </h3>
        <ul className="text-xs text-blue-700 space-y-1">
          <li>• Your amounts are encrypted with FHE</li>
          <li>• Matching happens on encrypted values</li>
          <li>• If match found: P2P settlement (no AMM)</li>
          <li>• If no match: Falls back to regular AMM swap</li>
          <li>• Settlement happens automatically after ~10 blocks</li>
        </ul>
      </div>

      {/* Approval Status */}
      {address && tokenSymbol && (
        <div className="mb-4 p-3 bg-gray-50 border border-gray-200 rounded">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs font-medium text-gray-700">
                {tokenSymbol} Approval Status
              </p>
              <p className="text-xs text-gray-500 mt-1">
                {hasAllowance() ? (
                  <span className="text-green-600">✓ Approved</span>
                ) : (
                  <span className="text-orange-600">⚠ Needs Approval</span>
                )}
              </p>
            </div>
            {!hasAllowance() && (
              <button
                onClick={handleApprove}
                disabled={approving}
                className="px-4 py-2 bg-orange-600 text-white text-sm font-semibold rounded hover:bg-orange-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
              >
                {approving ? 'Approving...' : 'Approve'}
              </button>
            )}
          </div>
        </div>
      )}

      {/* Submit Button */}
      <button
        onClick={handleSubmitIntent}
        disabled={loading || !address || !hasAllowance() || (useFHE && (!cofheClient || fheLoading))}
        className="w-full px-6 py-3 bg-blue-600 text-white font-semibold rounded hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
      >
        {loading ? (
          <span className="flex items-center justify-center">
            <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            Processing...
          </span>
        ) : useFHE && fheLoading ? 'Loading FHE...' : !hasAllowance() ? 'Approve Token First' : useFHE ? 'Submit Private Intent' : 'Submit Swap Intent (Demo)'}
      </button>

      {/* Transaction Hash */}
      {txHash && (
        <div className="mt-4 p-3 bg-green-50 border border-green-200 rounded">
          <p className="text-xs font-medium text-green-900">
            Transaction Submitted!
          </p>
          <a
            href={`https://sepolia.etherscan.io/tx/${txHash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs text-green-700 hover:underline break-all"
          >
            {txHash}
          </a>
        </div>
      )}

      {/* Help Text */}
      <div className="mt-6 p-4 bg-gray-50 border border-gray-200 rounded">
        <p className="text-xs font-semibold text-gray-700 mb-2">How to Use</p>
        <div className="text-xs text-gray-600 space-y-1">
          <ol className="list-decimal ml-4 space-y-1">
            <li>Enter token addresses above (or use the defaults)</li>
            <li>Make sure you have a balance of the input token</li>
            <li>Approve the token for SwapTest</li>
            <li>Enter amount and select slippage</li>
            <li>Click swap!</li>
          </ol>
          <p className="mt-2 text-xs text-orange-600">
            ⚠️ Note: Pool must exist with liquidity. If swap fails, the pool may not be initialized.
          </p>
        </div>
      </div>

      {/* Contract Info */}
      <div className="mt-4 p-3 bg-gray-50 border border-gray-200 rounded">
        <p className="text-xs font-semibold text-gray-700 mb-2">Deployed Contracts (Sepolia)</p>
        <div className="space-y-1 text-xs text-gray-600 font-mono">
          <p className="truncate">AIMHook: {AIM_HOOK}</p>
          <p className="truncate">SwapTest: {SWAP_TEST}</p>
        </div>
      </div>
    </div>
  );
}
