'use client';

import { useState, useEffect } from 'react';
import { useAccount, useWalletClient } from 'wagmi';
import { FhenixClient, Permit } from 'fhenixjs';
import { ethers } from 'ethers';

interface PermitInfo {
  contractAddress: string;
  expiresAt: Date;
  created: Date;
}

export default function PermitManager() {
  const { address } = useAccount();
  const { data: walletClient } = useWalletClient();
  const [permits, setPermits] = useState<PermitInfo[]>([]);
  const [creating, setCreating] = useState(false);
  const [duration, setDuration] = useState<'1day' | '1week' | '1month'>('1week');

  const hookAddress = process.env.NEXT_PUBLIC_AIM_HOOK || '';

  const createPermit = async () => {
    if (!walletClient || !address) {
      alert('Please connect wallet');
      return;
    }

    try {
      setCreating(true);

      // Calculate expiry time
      const now = new Date();
      const expiry = new Date(now);
      switch (duration) {
        case '1day':
          expiry.setDate(expiry.getDate() + 1);
          break;
        case '1week':
          expiry.setDate(expiry.getDate() + 7);
          break;
        case '1month':
          expiry.setMonth(expiry.getMonth() + 1);
          break;
      }

      console.log('Creating permit for:', hookAddress);
      console.log('Expires at:', expiry);

      // Create an ethers-compatible signer from walletClient
      const provider = new ethers.BrowserProvider(window.ethereum as any);
      const signer = await provider.getSigner();

      // Initialize Fhenix client with CoFHE proxy provider
      const fhenixRpc = process.env.NEXT_PUBLIC_FHENIX_RPC || 'https://api.helium.fhenix.zone';

      const fhenixProvider = {
        request: async (args: any) => {
          // Intercept FHE-specific RPC calls
          if (args.method === 'eth_getPublicKey' || args.method === 'fhe_getPublicKey') {
            console.log('Fetching FHE public key from Fhenix CoFHE for permit...');
            const response = await fetch(fhenixRpc, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                jsonrpc: '2.0',
                id: 1,
                method: args.method,
                params: args.params || []
              })
            });
            const data = await response.json();
            if (data.error) throw new Error(data.error.message);
            return data.result;
          }

          if (args.method === 'eth_chainId') {
            return '0xaa36a7'; // Sepolia chainId in hex
          }

          return window.ethereum?.request(args);
        }
      };

      const fhenixClient = new FhenixClient({ provider: fhenixProvider as any });

      // Create permit (allows contract to request decryption of user's encrypted values)
      const permit = await fhenixClient.generatePermit(
        hookAddress,
        signer,
        expiry
      );

      // Store permit info locally
      const newPermit: PermitInfo = {
        contractAddress: hookAddress,
        expiresAt: expiry,
        created: now,
      };

      setPermits([newPermit, ...permits]);

      // Store in localStorage for persistence
      const stored = localStorage.getItem('fhe-permits') || '[]';
      const allPermits = JSON.parse(stored);
      allPermits.push(newPermit);
      localStorage.setItem('fhe-permits', JSON.stringify(allPermits));

      alert('Permit created successfully! The hook can now decrypt your intent amounts.');

    } catch (error: any) {
      console.error('Error creating permit:', error);
      alert(`Error: ${error.message}`);
    } finally {
      setCreating(false);
    }
  };

  // Load permits from localStorage on mount
  useEffect(() => {
    const stored = localStorage.getItem('fhe-permits');
    if (stored) {
      try {
        const parsed = JSON.parse(stored);
        // Filter out expired permits
        const valid = parsed.filter((p: PermitInfo) =>
          new Date(p.expiresAt) > new Date()
        );
        setPermits(valid);
      } catch (e) {
        console.error('Error loading permits:', e);
      }
    }
  }, []);

  const isPermitExpiringSoon = (expiresAt: Date) => {
    const now = new Date();
    const expiry = new Date(expiresAt);
    const hoursUntilExpiry = (expiry.getTime() - now.getTime()) / (1000 * 60 * 60);
    return hoursUntilExpiry < 24;
  };

  return (
    <div className="max-w-2xl mx-auto p-6 bg-white rounded-lg shadow-lg">
      <h2 className="text-2xl font-bold mb-4 text-gray-800">FHE Permit Management</h2>

      <div className="mb-6 p-4 bg-yellow-50 border border-yellow-200 rounded">
        <h3 className="text-sm font-semibold text-yellow-900 mb-2">
          ⚠️ Why Permits Are Required
        </h3>
        <p className="text-xs text-yellow-700">
          Fhenix FHE coprocessor requires <strong>permits</strong> to decrypt your encrypted values.
          Without a valid permit, the hook cannot access decrypted amounts for settlement.
          Create a permit before submitting intents!
        </p>
      </div>

      {/* Create New Permit */}
      <div className="mb-6 p-4 border border-gray-200 rounded">
        <h3 className="font-semibold mb-3">Create New Permit</h3>

        <div className="mb-4">
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Permit Duration
          </label>
          <div className="flex space-x-3">
            {(['1day', '1week', '1month'] as const).map((d) => (
              <button
                key={d}
                onClick={() => setDuration(d)}
                className={`flex-1 px-4 py-2 rounded text-sm ${
                  duration === d
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                }`}
              >
                {d === '1day' && '1 Day'}
                {d === '1week' && '1 Week'}
                {d === '1month' && '1 Month'}
              </button>
            ))}
          </div>
        </div>

        <button
          onClick={createPermit}
          disabled={creating || !address}
          className="w-full px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-gray-400"
        >
          {creating ? 'Creating Permit...' : 'Create Permit'}
        </button>
      </div>

      {/* Active Permits */}
      <div>
        <h3 className="font-semibold mb-3">Active Permits</h3>

        {permits.length === 0 ? (
          <div className="text-center py-6 text-gray-500 border border-dashed border-gray-300 rounded">
            <p className="text-sm">No active permits</p>
            <p className="text-xs mt-1">Create a permit above to enable decryption</p>
          </div>
        ) : (
          <div className="space-y-3">
            {permits.map((permit, index) => (
              <div
                key={index}
                className={`p-4 border rounded ${
                  isPermitExpiringSoon(permit.expiresAt)
                    ? 'border-yellow-300 bg-yellow-50'
                    : 'border-gray-200'
                }`}
              >
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium">
                    {isPermitExpiringSoon(permit.expiresAt) ? '⚠️' : '✅'} AIMHook Permit
                  </span>
                  <span className="text-xs text-gray-500">
                    Created: {new Date(permit.created).toLocaleDateString()}
                  </span>
                </div>

                <div className="text-xs text-gray-600">
                  <p>Contract: {permit.contractAddress.slice(0, 10)}...{permit.contractAddress.slice(-8)}</p>
                  <p className={isPermitExpiringSoon(permit.expiresAt) ? 'text-yellow-700 font-semibold' : ''}>
                    Expires: {new Date(permit.expiresAt).toLocaleString()}
                  </p>
                </div>

                {isPermitExpiringSoon(permit.expiresAt) && (
                  <p className="mt-2 text-xs text-yellow-700">
                    ⏰ Expiring soon! Create a new permit to continue using the hook.
                  </p>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Info */}
      <div className="mt-6 p-3 bg-blue-50 border border-blue-200 rounded text-xs text-blue-700">
        <p>
          <strong>Note:</strong> Permits are stored locally in your browser. If you clear browser data,
          you'll need to recreate permits. Permits only grant decryption access to the specific contract address.
        </p>
      </div>
    </div>
  );
}
