'use client';

import { useState } from 'react';
import { useAccount } from 'wagmi';
import { useFhenix } from './FhenixProvider';

export default function PermitManager() {
  const { address } = useAccount();
  const { cofheClient, isLoading, error } = useFhenix();
  const [showDetails, setShowDetails] = useState(false);

  const hookAddress = process.env.NEXT_PUBLIC_AIM_HOOK || '';

  if (!address) {
    return (
      <div className="max-w-md mx-auto p-6 bg-white rounded-lg shadow-lg">
        <h2 className="text-2xl font-bold mb-4 text-gray-800">CoFHE Permits</h2>
        <p className="text-gray-500">Connect wallet to view permit status</p>
      </div>
    );
  }

  return (
    <div className="max-w-md mx-auto p-6 bg-white rounded-lg shadow-lg">
      <h2 className="text-2xl font-bold mb-4 text-gray-800">
        CoFHE Permit Manager
      </h2>

      <div className="space-y-4">
        {/* Status */}
        <div className="p-4 bg-blue-50 border border-blue-200 rounded">
          <h3 className="font-semibold text-blue-900 mb-2">Permit Status</h3>

          {isLoading ? (
            <p className="text-sm text-blue-700">Loading CoFHE client...</p>
          ) : error ? (
            <p className="text-sm text-red-700">Error: {error}</p>
          ) : cofheClient ? (
            <div>
              <p className="text-sm text-green-700 mb-2">
                ✓ CoFHE permit created successfully
              </p>
              <p className="text-xs text-blue-600">
                Permit allows {hookAddress} to decrypt your encrypted swap intents
              </p>
            </div>
          ) : (
            <p className="text-sm text-gray-700">No permit created yet</p>
          )}
        </div>

        {/* Details */}
        {cofheClient && (
          <div className="p-4 bg-gray-50 border border-gray-200 rounded">
            <button
              onClick={() => setShowDetails(!showDetails)}
              className="w-full text-left font-semibold text-gray-900 flex items-center justify-between"
            >
              <span>Technical Details</span>
              <span>{showDetails ? '▼' : '▶'}</span>
            </button>

            {showDetails && (
              <div className="mt-3 space-y-2 text-xs text-gray-600">
                <div>
                  <span className="font-medium">Contract:</span>
                  <p className="font-mono break-all">{hookAddress}</p>
                </div>
                <div>
                  <span className="font-medium">Your Address:</span>
                  <p className="font-mono break-all">{address}</p>
                </div>
                <div className="pt-2 border-t border-gray-300">
                  <p className="text-xs">
                    <strong>How it works:</strong> The permit allows the AIMHook contract
                    to request decryption of your encrypted values from the Fhenix CoFHE
                    coprocessor when matching intents. Your encrypted data remains private
                    on-chain and is only decrypted by the secure CoFHE system.
                  </p>
                </div>
              </div>
            )}
          </div>
        )}

        {/* Info */}
        <div className="p-4 bg-yellow-50 border border-yellow-200 rounded">
          <h3 className="text-sm font-semibold text-yellow-900 mb-2">
            ℹ️ About CoFHE Permits
          </h3>
          <p className="text-xs text-yellow-700">
            Permits are automatically created when you enable FHE mode. They allow
            the smart contract to request decryption of your encrypted swap amounts
            via the Fhenix CoFHE coprocessor. This happens securely off-chain and
            results are returned to the contract.
          </p>
        </div>

        {/* Refresh Button */}
        <button
          onClick={() => window.location.reload()}
          className="w-full px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
          disabled={isLoading}
        >
          {isLoading ? 'Loading...' : 'Refresh Permit Status'}
        </button>
      </div>
    </div>
  );
}
