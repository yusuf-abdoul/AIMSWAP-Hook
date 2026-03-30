'use client';

import React, { createContext, useContext, useState, useCallback } from 'react';
import { useAccount, useChainId } from 'wagmi';

interface EncryptedInput {
  ctHash: bigint;
  securityZone: number;
  utype: number;
  signature: `0x${string}`;
}

interface FhenixContextType {
  cofheClient: {
    encrypt: (value: bigint, type: 'uint128' | 'bool') => Promise<EncryptedInput>;
    unseal: (ciphertext: string) => Promise<bigint>;
  } | null;
  isLoading: boolean;
  error: string | null;
  initialize: () => Promise<void>;
  isReady: boolean;
}

const FhenixContext = createContext<FhenixContextType>({
  cofheClient: null,
  isLoading: false,
  error: null,
  initialize: async () => {},
  isReady: false,
});

export const useFhenix = () => useContext(FhenixContext);

// Module-level state (singleton)
let cofheModule: any = null;
let sessionReady = false;

async function loadCofhe() {
  if (cofheModule) return cofheModule;
  if (typeof window === 'undefined') throw new Error('Browser only');
  cofheModule = await import('cofhejs/web');
  return cofheModule;
}

/**
 * FhenixProvider - Client-side CoFHE using cofhejs/web with user's wallet.
 * Follows the pheatherx reference pattern.
 */
export function FhenixProvider({ children }: { children: React.ReactNode }) {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isReady, setIsReady] = useState(false);
  const { address, isConnected } = useAccount();
  const chainId = useChainId();

  const initialize = useCallback(async () => {
    if (!isConnected || !address) {
      setError('Connect wallet first');
      return;
    }

    if (sessionReady) {
      setIsReady(true);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const { cofhejs } = await loadCofhe();

      // Get ethers provider/signer from window.ethereum
      const { BrowserProvider } = await import('ethers');
      const browserProvider = new BrowserProvider(window.ethereum as any);
      const signer = await browserProvider.getSigner();

      console.log('[FHE] Initializing cofhejs/web with user wallet...');

      const result = await cofhejs.initializeWithEthers({
        ethersProvider: browserProvider,
        ethersSigner: signer,
        environment: 'TESTNET',
        generatePermit: true,
      });

      if (!result.success) {
        throw new Error(result.error?.message || 'cofhejs init failed');
      }

      console.log('[FHE] Session ready');
      sessionReady = true;
      setIsReady(true);
    } catch (err: any) {
      console.error('[FHE] Init failed:', err);
      setError(err.message || 'FHE initialization failed');
    } finally {
      setIsLoading(false);
    }
  }, [address, isConnected, chainId]);

  const cofheClient = isReady ? {
    encrypt: async (value: bigint, type: 'uint128' | 'bool'): Promise<EncryptedInput> => {
      const { cofhejs, Encryptable } = await loadCofhe();

      const encryptable = type === 'uint128'
        ? Encryptable.uint128(value)
        : Encryptable.bool(Boolean(value));

      const result = await cofhejs.encrypt([encryptable]);

      if (!result.success || !result.data) {
        throw new Error(result.error?.message || 'Encrypt failed');
      }

      const item = result.data[0];
      return {
        ctHash: BigInt(item.ctHash),
        securityZone: item.securityZone ?? 0,
        utype: item.utype ?? (type === 'uint128' ? 6 : 0),
        signature: (item.signature || '0x') as `0x${string}`,
      };
    },

    unseal: async (ciphertext: string): Promise<bigint> => {
      const { cofhejs, FheTypes } = await loadCofhe();
      const result = await cofhejs.unseal(BigInt(ciphertext), FheTypes.Uint128);

      if (!result.success || result.data === null || result.data === undefined) {
        throw new Error(result.error?.message || 'Unseal failed');
      }

      return BigInt(result.data.toString());
    },
  } : null;

  return (
    <FhenixContext.Provider value={{ cofheClient, isLoading, error, initialize, isReady }}>
      {children}
    </FhenixContext.Provider>
  );
}
