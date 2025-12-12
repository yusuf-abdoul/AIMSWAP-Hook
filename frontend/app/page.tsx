import dynamic from 'next/dynamic';
import WalletConnect from '../components/WalletConnect';

// Dynamically import components that use fhenixjs (WASM) - client-side only
const SwapIntent = dynamic(() => import('../components/SwapIntent'), {
  ssr: false,
  loading: () => <div className="text-center p-8">Loading swap interface...</div>
});

const IntentHistory = dynamic(() => import('../components/IntentHistory'), {
  ssr: false,
  loading: () => <div className="text-center p-8">Loading intent history...</div>
});

const PermitManager = dynamic(() => import('../components/PermitManager'), {
  ssr: false,
  loading: () => <div className="text-center p-8">Loading permit manager...</div>
});

export default function Home() {
  return (
    <main className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 py-12 px-4">
      <div className="container mx-auto">
        {/* Wallet Connection */}
        <WalletConnect />

        {/* Header */}
        <div className="text-center mb-12">
          <h1 className="text-4xl font-bold text-gray-900 mb-4">
            AIMHook - Privacy-Preserving CoW Protocol
          </h1>
          <p className="text-lg text-gray-600 max-w-2xl mx-auto">
            Encrypted intent matching for Uniswap v4 using Fhenix FHE Coprocessor.
            Submit private swap intents and get matched P2P or fall back to AMM.
          </p>
        </div>

        {/* Permit Management - CRITICAL for FHE decryption */}
        <div className="mb-8">
          <PermitManager />
        </div>

        {/* Swap Component */}
        <div className="mb-8">
          <SwapIntent />
        </div>

        {/* Intent History - Shows pending, matched, settled */}
        <div className="mb-8">
          <IntentHistory />
        </div>

        {/* How It Works */}
        <div className="max-w-4xl mx-auto mt-16 grid md:grid-cols-3 gap-6">
          <div className="bg-white p-6 rounded-lg shadow">
            <div className="text-3xl mb-4">🔒</div>
            <h3 className="font-bold text-lg mb-2">1. Encrypt Intent</h3>
            <p className="text-sm text-gray-600">
              Your swap amount and minimum return are encrypted client-side using FHE
            </p>
          </div>

          <div className="bg-white p-6 rounded-lg shadow">
            <div className="text-3xl mb-4">🔍</div>
            <h3 className="font-bold text-lg mb-2">2. Find Match</h3>
            <p className="text-sm text-gray-600">
              Hook matches your intent with opposite direction without revealing amounts
            </p>
          </div>

          <div className="bg-white p-6 rounded-lg shadow">
            <div className="text-3xl mb-4">💱</div>
            <h3 className="font-bold text-lg mb-2">3. Settle P2P</h3>
            <p className="text-sm text-gray-600">
              If matched, direct peer-to-peer settlement. Otherwise, AMM swap.
            </p>
          </div>
        </div>

        {/* Stats */}
        <div className="max-w-2xl mx-auto mt-12 bg-white p-6 rounded-lg shadow">
          <h3 className="font-bold text-lg mb-4 text-center">Benefits</h3>
          <div className="grid grid-cols-2 gap-4 text-center">
            <div>
              <div className="text-2xl font-bold text-blue-600">0%</div>
              <div className="text-sm text-gray-600">Slippage on Matches</div>
            </div>
            <div>
              <div className="text-2xl font-bold text-blue-600">100%</div>
              <div className="text-sm text-gray-600">Privacy Preserved</div>
            </div>
            <div>
              <div className="text-2xl font-bold text-blue-600">~10</div>
              <div className="text-sm text-gray-600">Blocks to Settlement</div>
            </div>
            <div>
              <div className="text-2xl font-bold text-blue-600">P2P</div>
              <div className="text-sm text-gray-600">Direct Settlement</div>
            </div>
          </div>
        </div>
      </div>
    </main>
  );
}
