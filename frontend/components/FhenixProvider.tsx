'use client';

import React, { createContext, useContext, useState, useEffect } from 'react';
import { usePublicClient, useWalletClient } from 'wagmi';

interface FhenixContextType {
  cofheClient: any | null;
  isLoading: boolean;
  error: string | null;
}

const FhenixContext = createContext<FhenixContextType>({
  cofheClient: null,
  isLoading: true,
  error: null,
});

export const useFhenix = () => useContext(FhenixContext);

export function FhenixProvider({ children }: { children: React.ReactNode }) {
  const [cofheClient, setCofheClient] = useState<any | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const publicClient = usePublicClient();
  const { data: walletClient } = useWalletClient();

  useEffect(() => {
    async function initCofhe() {
      if (typeof window === 'undefined') {
        setIsLoading(false);
        return;
      }

      if (!publicClient || !walletClient) {
        setIsLoading(false);
        return;
      }

      try {
        setIsLoading(true);
        console.log('Initializing cofhejs for CoFHE on Sepolia...');

        // Dynamically import cofhejs/web for browser environment
        const { cofhejs, Encryptable } = await import('cofhejs/web');

        console.log('Imported cofhejs successfully');
        console.log('Provider chain ID:', await publicClient.getChainId());

        // Initialize with Sepolia provider and wallet signer
        console.log('Calling cofhejs.initialize...');
        const initResult = await cofhejs.initialize({
          provider: publicClient as any,
          signer: walletClient as any
        });

        console.log('cofhejs.initialize result:', initResult);
        console.log('cofhejs initialized successfully');

        // Create permit for decryption access
        console.log('Creating CoFHE permit...');
        const permitResult = await cofhejs.createPermit();
        console.log('Permit result:', permitResult);
        console.log('Permit created successfully');

        // Get and log the permit
        const permit = cofhejs.getPermit();
        console.log('Retrieved permit:', permit);

        // Store both cofhejs and Encryptable helper
        setCofheClient({ cofhejs, Encryptable });
        setError(null);
        console.log('CoFHE client ready for Sepolia!');
      } catch (err: any) {
        console.error('Failed to initialize cofhejs:', err);
        console.error('Error stack:', err.stack);
        setError(err.message || 'Failed to initialize CoFHE client');
      } finally {
        setIsLoading(false);
      }
    }

    initCofhe();
  }, [publicClient, walletClient]);

  return (
    <FhenixContext.Provider value={{ cofheClient, isLoading, error }}>
      {children}
    </FhenixContext.Provider>
  );
}
