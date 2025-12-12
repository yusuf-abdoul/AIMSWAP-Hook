'use client';

import React, { createContext, useContext, useState, useEffect } from 'react';
import { FhenixClient } from 'fhenixjs';
import { usePublicClient } from 'wagmi';

interface FhenixContextType {
  fhenixClient: FhenixClient | null;
  isLoading: boolean;
  error: string | null;
}

const FhenixContext = createContext<FhenixContextType>({
  fhenixClient: null,
  isLoading: true,
  error: null,
});

export const useFhenix = () => useContext(FhenixContext);

export function FhenixProvider({ children }: { children: React.ReactNode }) {
  const [fhenixClient, setFhenixClient] = useState<FhenixClient | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const publicClient = usePublicClient();

  useEffect(() => {
    async function initFhenix() {
      if (typeof window === 'undefined') {
        setIsLoading(false);
        return;
      }

      try {
        setIsLoading(true);
        console.log('Initializing FhenixClient for CoFHE...');

        // Create a provider that proxies FHE-specific calls to Fhenix CoFHE API
        const fhenixRpc = process.env.NEXT_PUBLIC_FHENIX_RPC || 'https://api.helium.fhenix.zone';

        const provider = {
          request: async (args: any) => {
            // Intercept FHE-specific RPC calls and forward to Fhenix API
            if (args.method === 'eth_getPublicKey' || args.method === 'fhe_getPublicKey') {
              console.log('Fetching FHE public key from Fhenix CoFHE...');
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

            // For chain ID, return Unichain Sepolia
            if (args.method === 'eth_chainId') {
              return '0x515'; // 1301 in hex
            }

            // For other calls, use the Sepolia provider
            if (publicClient && (publicClient as any).request) {
              return (publicClient as any).request(args);
            }

            // Fallback to window.ethereum
            if (window.ethereum) {
              return window.ethereum.request(args);
            }

            throw new Error(`Unsupported method: ${args.method}`);
          }
        };

        const client = new FhenixClient({ provider: provider as any });

        setFhenixClient(client);
        setError(null);
        console.log('FhenixClient initialized successfully with CoFHE');
      } catch (err: any) {
        console.error('Failed to initialize FhenixClient:', err);
        setError(err.message || 'Failed to initialize FHE client');
      } finally {
        setIsLoading(false);
      }
    }

    if (publicClient) {
      initFhenix();
    }
  }, [publicClient]);

  return (
    <FhenixContext.Provider value={{ fhenixClient, isLoading, error }}>
      {children}
    </FhenixContext.Provider>
  );
}
