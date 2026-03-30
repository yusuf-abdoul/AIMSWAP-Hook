'use client';

import { RainbowKitProvider, getDefaultConfig } from '@rainbow-me/rainbowkit';
import { WagmiProvider } from 'wagmi';
import { sepolia, arbitrumSepolia } from 'wagmi/chains';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { http } from 'viem';
import { FhenixProvider } from '../components/FhenixProvider';

// Supported chains:
// - Arbitrum Sepolia (421614) - PRIMARY, recommended for CoFHE
// - Ethereum Sepolia (11155111) - secondary
const config = getDefaultConfig({
  appName: 'AIMHook',
  projectId: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID || 'YOUR_PROJECT_ID',
  chains: [arbitrumSepolia, sepolia],
  transports: {
    [arbitrumSepolia.id]: http(
      process.env.NEXT_PUBLIC_ARB_SEPOLIA_RPC || 'https://sepolia-rollup.arbitrum.io/rpc'
    ),
    [sepolia.id]: http(
      process.env.NEXT_PUBLIC_ETH_SEPOLIA_RPC || 'https://ethereum-sepolia-rpc.publicnode.com'
    ),
  },
  ssr: true,
});

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
