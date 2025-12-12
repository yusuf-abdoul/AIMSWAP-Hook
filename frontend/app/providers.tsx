'use client';

import { RainbowKitProvider, getDefaultConfig } from '@rainbow-me/rainbowkit';
import { WagmiProvider } from 'wagmi';
import { sepolia } from 'wagmi/chains';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { http } from 'viem';
import { FhenixProvider } from '../components/FhenixProvider';

// CoFHE Coprocessor Mode Configuration
// Deploy AIMHook on Sepolia (where Uniswap v4 PoolManager is deployed)
// Fhenix is used as a SERVICE for FHE operations (like Chainlink/Gelato)
// DO NOT deploy to Fhenix - only call it for client-side encryption

// Configure wagmi with viem transports (wagmi v2 API)
const config = getDefaultConfig({
  appName: 'AIMHook',
  projectId: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID || 'YOUR_PROJECT_ID',
  chains: [sepolia],
  transports: {
    [sepolia.id]: http(process.env.NEXT_PUBLIC_RPC_URL || 'https://ethereum-sepolia-rpc.publicnode.com'),
  },
  ssr: true, // Enable server-side rendering
});

// Create QueryClient for React Query (required by wagmi v2)
const queryClient = new QueryClient();

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider modalSize="compact">
          <FhenixProvider>
            {children}
          </FhenixProvider>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
