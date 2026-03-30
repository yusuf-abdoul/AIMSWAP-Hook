'use client';

import { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import { useAccount, useWalletClient, usePublicClient } from 'wagmi';
import { useFhenix } from './FhenixProvider';

// ERC20 ABI (minimal)
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
    inputs: [{ name: 'account', type: 'address' }],
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

// Block explorer URLs per chain
const EXPLORERS: Record<number, string> = {
  421614: 'https://sepolia.arbiscan.io',
  11155111: 'https://sepolia.etherscan.io',
};

/**
 * SwapIntent Component
 * Creates encrypted swap intents via server-side CoFHE API.
 */
export default function SwapIntent() {
  const { address, chain } = useAccount();
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();
  const { cofheClient, isLoading: fheLoading, error: fheError, initialize: initFhe, isReady: fheReady } = useFhenix();

  const [inputAmount, setInputAmount] = useState('');
  const [slippage, setSlippage] = useState('0.5');
  const [zeroForOne, setZeroForOne] = useState(true);
  const [loading, setLoading] = useState(false);
  const [encrypting, setEncrypting] = useState(false);
  const [approving, setApproving] = useState(false);
  const [txHash, setTxHash] = useState('');
  const [allowance, setAllowance] = useState<bigint>(0n);
  const [tokenSymbol, setTokenSymbol] = useState<string>('');
  const [useFHE, setUseFHE] = useState(true); // FHE enabled by default now

  // Token addresses
  const [token0Input, setToken0Input] = useState(process.env.NEXT_PUBLIC_TOKEN0 || '');
  const [token1Input, setToken1Input] = useState(process.env.NEXT_PUBLIC_TOKEN1 || '');
  const [token0Symbol, setToken0Symbol] = useState('Token0');
  const [token1Symbol, setToken1Symbol] = useState('Token1');
  const [token0Balance, setToken0Balance] = useState<string>('0');
  const [token1Balance, setToken1Balance] = useState<string>('0');
  const [token0Decimals, setToken0Decimals] = useState<number>(18);
  const [token1Decimals, setToken1Decimals] = useState<number>(18);

  // Contract addresses
  const SWAP_TEST = process.env.NEXT_PUBLIC_SWAP_ROUTER || process.env.NEXT_PUBLIC_SWAP_TEST || '';
  const AIM_HOOK = process.env.NEXT_PUBLIC_AIM_HOOK || '';

  const TOKEN0 = token0Input;
  const TOKEN1 = token1Input;

  const getInputToken = () => (zeroForOne ? TOKEN0 : TOKEN1);

  const explorerUrl = chain?.id ? EXPLORERS[chain.id] || EXPLORERS[421614] : EXPLORERS[421614];

  // Fetch token info
  useEffect(() => {
    const fetchTokenInfo = async () => {
      if (!publicClient || !address) return;
      try {
        if (TOKEN0 && ethers.isAddress(TOKEN0)) {
          const [symbol0, balance0, decimals0] = await Promise.all([
            publicClient.readContract({ address: TOKEN0 as `0x${string}`, abi: ERC20_ABI, functionName: 'symbol' } as any),
            publicClient.readContract({ address: TOKEN0 as `0x${string}`, abi: ERC20_ABI, functionName: 'balanceOf', args: [address] } as any),
            publicClient.readContract({ address: TOKEN0 as `0x${string}`, abi: ERC20_ABI, functionName: 'decimals' } as any),
          ]);
          setToken0Symbol(symbol0 as string);
          setToken0Decimals(decimals0 as number);
          setToken0Balance(ethers.formatUnits(balance0 as bigint, decimals0 as number));
        }
        if (TOKEN1 && ethers.isAddress(TOKEN1)) {
          const [symbol1, balance1, decimals1] = await Promise.all([
            publicClient.readContract({ address: TOKEN1 as `0x${string}`, abi: ERC20_ABI, functionName: 'symbol' } as any),
            publicClient.readContract({ address: TOKEN1 as `0x${string}`, abi: ERC20_ABI, functionName: 'balanceOf', args: [address] } as any),
            publicClient.readContract({ address: TOKEN1 as `0x${string}`, abi: ERC20_ABI, functionName: 'decimals' } as any),
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

  // Check allowance
  useEffect(() => {
    const checkAllowance = async () => {
      if (!address || !publicClient || !SWAP_TEST) return;
      try {
        const inputToken = getInputToken();
        if (!inputToken || !ethers.isAddress(inputToken)) return;
        const currentAllowance = await publicClient.readContract({
          address: inputToken as `0x${string}`, abi: ERC20_ABI,
          functionName: 'allowance', args: [address, SWAP_TEST as `0x${string}`]
        } as any);
        const symbol = await publicClient.readContract({
          address: inputToken as `0x${string}`, abi: ERC20_ABI, functionName: 'symbol'
        } as any);
        setAllowance(currentAllowance as bigint);
        setTokenSymbol(symbol as string);
      } catch (error) {
        console.error('Error checking allowance:', error);
      }
    };
    checkAllowance();
  }, [address, publicClient, SWAP_TEST, zeroForOne, TOKEN0, TOKEN1]);

  const handleApprove = async () => {
    if (!walletClient || !address || !publicClient) return;
    try {
      setApproving(true);
      const inputToken = getInputToken();
      const hash = await walletClient.writeContract({
        address: inputToken as `0x${string}`,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [SWAP_TEST as `0x${string}`, ethers.MaxUint256]
      });
      await publicClient.waitForTransactionReceipt({ hash });
      const newAllowance = await publicClient.readContract({
        address: inputToken as `0x${string}`, abi: ERC20_ABI,
        functionName: 'allowance', args: [address, SWAP_TEST as `0x${string}`]
      } as any);
      setAllowance(newAllowance as bigint);
    } catch (error: any) {
      console.error('Approval failed:', error);
      alert(`Approval failed: ${error.message}`);
    } finally {
      setApproving(false);
    }
  };

  const hasAllowance = () => {
    if (!inputAmount) return true;
    try {
      const decimals = zeroForOne ? token0Decimals : token1Decimals;
      return allowance >= ethers.parseUnits(inputAmount, decimals);
    } catch { return false; }
  };

  const handleSubmitIntent = async () => {
    if (!walletClient || !address || !publicClient) {
      alert('Please connect wallet');
      return;
    }
    if (useFHE && !fheReady) {
      alert('CoFHE not initialized. Click "Initialize FHE" first.');
      return;
    }
    if (!inputAmount) {
      alert('Please enter amount');
      return;
    }

    try {
      setLoading(true);
      const inputDecimals = zeroForOne ? token0Decimals : token1Decimals;
      const amountWei = ethers.parseUnits(inputAmount, inputDecimals);
      const slippagePercent = parseFloat(slippage);
      const minReturnWei = (amountWei * BigInt(Math.floor((100 - slippagePercent) * 100))) / 10000n;

      let hookData: `0x${string}`;

      if (useFHE && cofheClient) {
        setEncrypting(true);
        console.log('[FHE] Encrypting amounts via server API...');

        const encryptedAmount = await cofheClient.encrypt(amountWei, 'uint128');
        const encryptedMinReturn = await cofheClient.encrypt(minReturnWei, 'uint128');
        setEncrypting(false);

        hookData = ethers.AbiCoder.defaultAbiCoder().encode(
          [
            'tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature)',
            'tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature)'
          ],
          [
            [encryptedAmount.ctHash, encryptedAmount.securityZone || 0, encryptedAmount.utype || 6, encryptedAmount.signature || '0x00'],
            [encryptedMinReturn.ctHash, encryptedMinReturn.securityZone || 0, encryptedMinReturn.utype || 6, encryptedMinReturn.signature || '0x00']
          ]
        ) as `0x${string}`;
      } else {
        // Demo mode: construct valid InEuint128 structs with deterministic ctHash
        console.log('[Demo] Using plain values (no encryption)');
        const amountSig = ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256'], [amountWei, amountWei]);
        const minReturnSig = ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256'], [minReturnWei, minReturnWei]);
        const amountHash = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'string'], [amountWei, 'amount']));
        const minReturnHash = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'string'], [minReturnWei, 'minReturn']));

        hookData = ethers.AbiCoder.defaultAbiCoder().encode(
          [
            'tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature)',
            'tuple(uint256 ctHash, uint8 securityZone, uint8 utype, bytes signature)'
          ],
          [
            [amountHash, 0, 6, amountSig],
            [minReturnHash, 0, 6, minReturnSig]
          ]
        ) as `0x${string}`;
      }

      const poolKey = {
        currency0: TOKEN0 as `0x${string}`,
        currency1: TOKEN1 as `0x${string}`,
        fee: 3000,
        tickSpacing: 60,
        hooks: AIM_HOOK as `0x${string}`
      };

      const swapParams = {
        zeroForOne,
        amountSpecified: -amountWei,
        sqrtPriceLimitX96: zeroForOne ? 4295128740n : 1461446703485210103287273052203988822378723970341n
      };

      // Fetch current gas price with buffer for Arbitrum Sepolia
      const gasPrice = await publicClient.getGasPrice();
      const maxFee = gasPrice * 3n; // 3x buffer to avoid "less than base fee" errors

      const hash = await walletClient.writeContract({
        address: SWAP_TEST as `0x${string}`,
        abi: [{
          name: 'swap',
          type: 'function',
          stateMutability: 'payable',
          inputs: [
            { name: 'key', type: 'tuple', components: [
              { name: 'currency0', type: 'address' },
              { name: 'currency1', type: 'address' },
              { name: 'fee', type: 'uint24' },
              { name: 'tickSpacing', type: 'int24' },
              { name: 'hooks', type: 'address' }
            ]},
            { name: 'params', type: 'tuple', components: [
              { name: 'zeroForOne', type: 'bool' },
              { name: 'amountSpecified', type: 'int256' },
              { name: 'sqrtPriceLimitX96', type: 'uint160' }
            ]},
            { name: 'testSettings', type: 'tuple', components: [
              { name: 'takeClaims', type: 'bool' },
              { name: 'settleUsingBurn', type: 'bool' }
            ]},
            { name: 'hookData', type: 'bytes' }
          ],
          outputs: [{ type: 'int256' }]
        }],
        functionName: 'swap',
        args: [poolKey, swapParams, { takeClaims: false, settleUsingBurn: false }, hookData],
        gas: 5000000n,
        maxFeePerGas: maxFee,
        maxPriorityFeePerGas: gasPrice / 2n > 0n ? gasPrice / 2n : 1n,
      });

      setTxHash(hash);
      await publicClient.waitForTransactionReceipt({ hash });
      alert('Intent submitted successfully!');
      setInputAmount('');
    } catch (error: any) {
      console.error('Error submitting intent:', error);
      let errorMsg = error.message || 'Unknown error';
      if (errorMsg.includes('PoolNotInitialized')) {
        errorMsg = 'Pool not initialized. Initialize a pool with these tokens first.';
      } else if (errorMsg.includes('insufficient') || errorMsg.includes('balance')) {
        errorMsg = 'Insufficient token balance.';
      } else if (errorMsg.includes('InvalidEncryptedInput')) {
        errorMsg = 'Invalid encrypted input. Make sure FHE is properly configured.';
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

      {/* Chain Indicator */}
      {chain && (
        <div className="mb-4 p-2 bg-gray-50 border border-gray-200 rounded text-xs text-gray-600 text-center">
          Connected to: <strong>{chain.name}</strong> (Chain ID: {chain.id})
          {chain.id !== 421614 && chain.id !== 11155111 && (
            <p className="text-orange-600 mt-1">Switch to Arbitrum Sepolia or Ethereum Sepolia for CoFHE support</p>
          )}
        </div>
      )}

      {/* Token Selection */}
      <div className="mb-4 p-4 bg-blue-50 border border-blue-200 rounded">
        <p className="text-sm font-semibold text-blue-900 mb-3">Token Pair</p>
        <div className="space-y-3">
          <div>
            <label className="block text-xs font-medium text-blue-900 mb-1">Token0 Address</label>
            <input type="text" value={token0Input} onChange={(e) => setToken0Input(e.target.value)}
              placeholder="0x..." className="w-full px-3 py-2 text-sm border border-blue-300 rounded focus:ring-2 focus:ring-blue-500 font-mono" />
            {token0Symbol && <p className="text-xs text-blue-700 mt-1">{token0Symbol} - Balance: {parseFloat(token0Balance).toFixed(4)}</p>}
          </div>
          <div>
            <label className="block text-xs font-medium text-blue-900 mb-1">Token1 Address</label>
            <input type="text" value={token1Input} onChange={(e) => setToken1Input(e.target.value)}
              placeholder="0x..." className="w-full px-3 py-2 text-sm border border-blue-300 rounded focus:ring-2 focus:ring-blue-500 font-mono" />
            {token1Symbol && <p className="text-xs text-blue-700 mt-1">{token1Symbol} - Balance: {parseFloat(token1Balance).toFixed(4)}</p>}
          </div>
        </div>
      </div>

      {/* FHE Toggle */}
      <div className="mb-4 p-4 bg-yellow-50 border border-yellow-200 rounded">
        <div className="flex items-center justify-between mb-2">
          <p className="text-sm font-semibold text-yellow-900">FHE Encryption</p>
          <label className="flex items-center space-x-2 cursor-pointer">
            <input type="checkbox" checked={useFHE} onChange={(e) => setUseFHE(e.target.checked)} className="rounded" />
            <span className="text-xs text-yellow-700">{useFHE ? 'Enabled' : 'Demo mode'}</span>
          </label>
        </div>
        <p className="text-xs text-yellow-700">
          {useFHE ? (
            fheLoading ? 'Initializing CoFHE session...' :
            fheError ? `Error: ${fheError}` :
            fheReady ? 'CoFHE ready (client-side encryption via cofhejs/web)' :
            'Not initialized - click below to start'
          ) : 'Demo mode - plain values, no encryption'}
        </p>
        {useFHE && !fheReady && !fheLoading && (
          <button onClick={initFhe}
            className="mt-2 w-full px-3 py-2 bg-yellow-600 text-white text-sm font-semibold rounded hover:bg-yellow-700 transition-colors">
            Initialize FHE Session
          </button>
        )}
      </div>

      {/* Swap Direction */}
      <div className="mb-4">
        <label className="block text-sm font-medium text-gray-700 mb-2">Swap Direction</label>
        <div className="flex space-x-4">
          <button onClick={() => setZeroForOne(true)}
            className={`flex-1 px-4 py-2 rounded transition-colors ${zeroForOne ? 'bg-blue-600 text-white' : 'bg-gray-200 text-gray-700 hover:bg-gray-300'}`}>
            {token0Symbol} → {token1Symbol}
          </button>
          <button onClick={() => setZeroForOne(false)}
            className={`flex-1 px-4 py-2 rounded transition-colors ${!zeroForOne ? 'bg-blue-600 text-white' : 'bg-gray-200 text-gray-700 hover:bg-gray-300'}`}>
            {token1Symbol} → {token0Symbol}
          </button>
        </div>
      </div>

      {/* Amount Input */}
      <div className="mb-4">
        <label className="block text-sm font-medium text-gray-700 mb-2">Amount to Swap</label>
        <input type="number" value={inputAmount}
          onChange={(e) => { if (e.target.value === '' || parseFloat(e.target.value) >= 0) setInputAmount(e.target.value); }}
          placeholder="0.0" min="0" step="0.01"
          className="w-full px-4 py-2 border border-gray-300 rounded focus:ring-2 focus:ring-blue-500" />
      </div>

      {/* Slippage */}
      <div className="mb-6">
        <label className="block text-sm font-medium text-gray-700 mb-2">Slippage Tolerance</label>
        <div className="flex space-x-2">
          {['0.1', '0.5', '1.0', '2.0'].map((s) => (
            <button key={s} onClick={() => setSlippage(s)}
              className={`flex-1 px-3 py-2 text-sm rounded transition-colors ${slippage === s ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-700 hover:bg-gray-200'}`}>
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
            <p className="text-sm font-medium text-blue-900">Encrypting with CoFHE...</p>
          </div>
        </div>
      )}

      {/* Approval Status */}
      {address && tokenSymbol && (
        <div className="mb-4 p-3 bg-gray-50 border border-gray-200 rounded">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs font-medium text-gray-700">{tokenSymbol} Approval</p>
              <p className="text-xs text-gray-500 mt-1">
                {hasAllowance() ? <span className="text-green-600">Approved</span> : <span className="text-orange-600">Needs Approval</span>}
              </p>
            </div>
            {!hasAllowance() && (
              <button onClick={handleApprove} disabled={approving}
                className="px-4 py-2 bg-orange-600 text-white text-sm font-semibold rounded hover:bg-orange-700 disabled:bg-gray-400 transition-colors">
                {approving ? 'Approving...' : 'Approve'}
              </button>
            )}
          </div>
        </div>
      )}

      {/* Submit Button */}
      <button onClick={handleSubmitIntent}
        disabled={loading || !address || !hasAllowance() || (useFHE && (!fheReady || fheLoading))}
        className="w-full px-6 py-3 bg-blue-600 text-white font-semibold rounded hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors">
        {loading ? 'Processing...' : useFHE && fheLoading ? 'Loading FHE...' : useFHE && !fheReady ? 'Initialize FHE First' : !hasAllowance() ? 'Approve Token First' : useFHE ? 'Submit Private Intent' : 'Submit Intent (Demo)'}
      </button>

      {/* Transaction Hash */}
      {txHash && (
        <div className="mt-4 p-3 bg-green-50 border border-green-200 rounded">
          <p className="text-xs font-medium text-green-900">Transaction Submitted!</p>
          <a href={`${explorerUrl}/tx/${txHash}`} target="_blank" rel="noopener noreferrer"
            className="text-xs text-green-700 hover:underline break-all">{txHash}</a>
        </div>
      )}

      {/* Contract Info */}
      <div className="mt-4 p-3 bg-gray-50 border border-gray-200 rounded">
        <p className="text-xs font-semibold text-gray-700 mb-2">Contracts</p>
        <div className="space-y-1 text-xs text-gray-600 font-mono">
          <p className="truncate">AIMHook: {AIM_HOOK}</p>
          <p className="truncate">SwapTest: {SWAP_TEST}</p>
        </div>
      </div>
    </div>
  );
}
