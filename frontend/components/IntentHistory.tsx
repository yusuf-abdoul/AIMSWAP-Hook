'use client';

import { useState, useEffect } from 'react';
import { useAccount, useWatchContractEvent } from 'wagmi';
import { ethers } from 'ethers';

interface Intent {
  intentId: string;
  poolId: string;
  owner: string;
  status: 'PENDING' | 'MATCHED' | 'SETTLED' | 'EXPIRED';
  createdBlock: number;
  expireBlock: number;
  txHash?: string;
}

const AIM_HOOK_ABI = [
  'event IntentCreated(bytes32 indexed poolId, bytes32 indexed intentId, address owner, uint256 amount, uint32 expireBlock)',
  'event IntentMatched(bytes32 indexed poolId, bytes32 indexed intentA, bytes32 indexed intentB, uint128 amountMatched)',
  'event IntentSettled(bytes32 indexed poolId, bytes32 indexed intentId, uint128 amountSettled)',
  'function ownerNonces(address owner) external view returns (uint256)',
];

export default function IntentHistory() {
  const { address } = useAccount();
  const [intents, setIntents] = useState<Intent[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const hookAddress = process.env.NEXT_PUBLIC_AIM_HOOK || '';

  // Listen for new IntentCreated events
  useWatchContractEvent({
    address: hookAddress as `0x${string}`,
    abi: AIM_HOOK_ABI,
    eventName: 'IntentCreated',
    onLogs(logs) {
      const newIntents = logs
        .filter((log: any) => log.args.owner?.toLowerCase() === address?.toLowerCase())
        .map((log: any) => ({
          intentId: log.args.intentId,
          poolId: log.args.poolId,
          owner: log.args.owner,
          status: 'PENDING' as const,
          createdBlock: log.blockNumber,
          expireBlock: Number(log.args.expireBlock),
          txHash: log.transactionHash,
        }));

      setIntents(prev => [...newIntents, ...prev]);
    },
  });

  // Listen for IntentMatched events
  useWatchContractEvent({
    address: hookAddress as `0x${string}`,
    abi: AIM_HOOK_ABI,
    eventName: 'IntentMatched',
    onLogs(logs) {
      logs.forEach((log: any) => {
        const intentAId = log.args.intentA;
        const intentBId = log.args.intentB;

        setIntents(prev =>
          prev.map(intent => {
            if (intent.intentId === intentAId || intent.intentId === intentBId) {
              return { ...intent, status: 'MATCHED' as const };
            }
            return intent;
          })
        );
      });
    },
  });

  // Listen for IntentSettled events
  useWatchContractEvent({
    address: hookAddress as `0x${string}`,
    abi: AIM_HOOK_ABI,
    eventName: 'IntentSettled',
    onLogs(logs) {
      logs.forEach((log: any) => {
        const intentId = log.args.intentId;

        setIntents(prev =>
          prev.map(intent => {
            if (intent.intentId === intentId) {
              return { ...intent, status: 'SETTLED' as const };
            }
            return intent;
          })
        );
      });
    },
  });

  const getStatusColor = (status: Intent['status']) => {
    switch (status) {
      case 'PENDING':
        return 'bg-yellow-100 text-yellow-800';
      case 'MATCHED':
        return 'bg-blue-100 text-blue-800';
      case 'SETTLED':
        return 'bg-green-100 text-green-800';
      case 'EXPIRED':
        return 'bg-gray-100 text-gray-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  const getStatusIcon = (status: Intent['status']) => {
    switch (status) {
      case 'PENDING':
        return '⏳';
      case 'MATCHED':
        return '🔍';
      case 'SETTLED':
        return '✅';
      case 'EXPIRED':
        return '❌';
      default:
        return '❓';
    }
  };

  if (!address) {
    return (
      <div className="max-w-4xl mx-auto p-6 bg-white rounded-lg shadow-lg">
        <p className="text-center text-gray-500">
          Connect wallet to view your intents
        </p>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto p-6 bg-white rounded-lg shadow-lg">
      <h2 className="text-2xl font-bold mb-6 text-gray-800">Your Intents</h2>

      {error && (
        <div className="mb-4 p-4 bg-red-50 border border-red-200 rounded">
          <p className="text-sm text-red-700">{error}</p>
        </div>
      )}

      {loading ? (
        <div className="text-center py-8">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
          <p className="mt-2 text-gray-600">Loading intents...</p>
        </div>
      ) : intents.length === 0 ? (
        <div className="text-center py-8 text-gray-500">
          <p>No intents yet. Submit your first encrypted swap above!</p>
        </div>
      ) : (
        <div className="space-y-4">
          {intents.map((intent, index) => (
            <div
              key={`${intent.intentId}-${index}`}
              className="border border-gray-200 rounded-lg p-4 hover:shadow-md transition-shadow"
            >
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center space-x-3">
                  <span className="text-2xl">{getStatusIcon(intent.status)}</span>
                  <div>
                    <span
                      className={`inline-block px-3 py-1 rounded-full text-xs font-semibold ${getStatusColor(
                        intent.status
                      )}`}
                    >
                      {intent.status}
                    </span>
                  </div>
                </div>
                <div className="text-xs text-gray-500">
                  Block #{intent.createdBlock}
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4 mt-3 text-sm">
                <div>
                  <span className="text-gray-500">Intent ID:</span>
                  <p className="font-mono text-xs break-all">
                    {intent.intentId.slice(0, 10)}...{intent.intentId.slice(-8)}
                  </p>
                </div>
                <div>
                  <span className="text-gray-500">Pool ID:</span>
                  <p className="font-mono text-xs break-all">
                    {intent.poolId.slice(0, 10)}...{intent.poolId.slice(-8)}
                  </p>
                </div>
              </div>

              {intent.status === 'PENDING' && (
                <div className="mt-3 text-xs text-gray-600">
                  <p>⏰ Expires at block #{intent.expireBlock}</p>
                  <p className="mt-1">
                    Waiting for opposite direction intent to match...
                  </p>
                </div>
              )}

              {intent.status === 'MATCHED' && (
                <div className="mt-3 text-xs text-blue-600">
                  <p>
                    🎯 Match found! Waiting for FHE coprocessor to decrypt (~10
                    blocks)
                  </p>
                </div>
              )}

              {intent.status === 'SETTLED' && (
                <div className="mt-3 text-xs text-green-600">
                  <p>✅ Settled successfully via P2P transfer!</p>
                </div>
              )}

              {intent.txHash && (
                <div className="mt-3">
                  <a
                    href={`https://explorer.helium.fhenix.zone/tx/${intent.txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs text-blue-600 hover:underline"
                  >
                    View Transaction →
                  </a>
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Info box about Fhenix coprocessor */}
      <div className="mt-6 p-4 bg-blue-50 border border-blue-200 rounded">
        <h3 className="text-sm font-semibold text-blue-900 mb-2">
          ℹ️ About Fhenix Coprocessor
        </h3>
        <p className="text-xs text-blue-700">
          Fhenix operates as a FHE coprocessor, not an L2. Encrypted computations
          happen off-chain in the coprocessor, and decrypted results are posted
          back to your chain. This is why settlement takes ~10 blocks.
        </p>
      </div>
    </div>
  );
}
