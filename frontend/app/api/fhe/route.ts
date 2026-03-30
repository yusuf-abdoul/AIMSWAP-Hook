/**
 * Server-side FHE API route using cofhejs/node
 *
 * cofhejs WASM fails in browser environments, so all FHE operations
 * (initialize, encrypt, unseal) are handled server-side via this API.
 *
 * Based on the pheatherx reference implementation.
 */
import { NextRequest, NextResponse } from 'next/server';
import { Wallet, JsonRpcProvider } from 'ethers';

// Session cache: chainId -> { cofheInstance, permit, expiry }
const sessions = new Map<
  string,
  { cofheInstance: any; permit: any; expiry: number }
>();

const SESSION_TTL_MS = 30 * 60 * 1000; // 30 minutes

// Supported chains for CoFHE
const SUPPORTED_CHAINS: Record<number, string> = {
  421614: 'https://sepolia-rollup.arbitrum.io/rpc',  // Arbitrum Sepolia (primary)
  11155111: 'https://ethereum-sepolia-rpc.publicnode.com', // Ethereum Sepolia
};

// Cleanup expired sessions periodically
setInterval(() => {
  const now = Date.now();
  for (const [key, session] of sessions.entries()) {
    if (session.expiry < now) {
      sessions.delete(key);
    }
  }
}, 60_000);

/**
 * Dynamic import of cofhejs/node to avoid static analysis issues
 */
async function loadCofhe() {
  // Use dynamic import for cofhejs/node (server-side WASM works reliably)
  const mod = await import('cofhejs/node');
  return mod;
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { action, chainId, value, type: encType } = body;

    switch (action) {
      case 'initialize': {
        if (!chainId || !SUPPORTED_CHAINS[chainId]) {
          return NextResponse.json(
            { error: `Unsupported chain ID: ${chainId}. Supported: ${Object.keys(SUPPORTED_CHAINS).join(', ')}` },
            { status: 400 }
          );
        }

        const sessionKey = `chain-${chainId}`;
        const existing = sessions.get(sessionKey);
        if (existing && existing.expiry > Date.now()) {
          return NextResponse.json({
            status: 'ready',
            chainId,
            message: 'Session already active',
          });
        }

        const rpcUrl = SUPPORTED_CHAINS[chainId];
        const provider = new JsonRpcProvider(rpcUrl);

        // Create a temporary session signer (not the user's wallet)
        const sessionWallet = Wallet.createRandom().connect(provider);

        const { cofhejs } = await loadCofhe();

        await cofhejs.initialize({
          provider: provider as any,
          signer: sessionWallet as any,
        });

        const permit = await cofhejs.createPermit();

        sessions.set(sessionKey, {
          cofheInstance: cofhejs,
          permit,
          expiry: Date.now() + SESSION_TTL_MS,
        });

        return NextResponse.json({
          status: 'ready',
          chainId,
          message: 'CoFHE session initialized',
        });
      }

      case 'encrypt': {
        // Find active session (use any available session)
        const session = findActiveSession();
        if (!session) {
          return NextResponse.json(
            { error: 'No active FHE session. Call initialize first.' },
            { status: 400 }
          );
        }

        const { cofheInstance } = session;
        const { Encryptable } = await loadCofhe();

        let ciphertext;
        if (encType === 'uint128') {
          ciphertext = await cofheInstance.encrypt(
            Encryptable.uint128(BigInt(value))
          );
        } else if (encType === 'bool') {
          ciphertext = await cofheInstance.encrypt(
            Encryptable.bool(Boolean(value))
          );
        } else {
          return NextResponse.json(
            { error: `Unsupported type: ${encType}` },
            { status: 400 }
          );
        }

        return NextResponse.json({ ciphertext });
      }

      case 'unseal': {
        const session = findActiveSession();
        if (!session) {
          return NextResponse.json(
            { error: 'No active FHE session. Call initialize first.' },
            { status: 400 }
          );
        }

        const { cofheInstance } = session;
        const { ciphertext: ct } = body;

        const plaintext = await cofheInstance.unseal(ct);

        return NextResponse.json({ plaintext: plaintext.toString() });
      }

      case 'status': {
        const session = findActiveSession();
        return NextResponse.json({
          hasSession: !!session,
          expiresIn: session
            ? Math.max(0, session.expiry - Date.now())
            : 0,
        });
      }

      default:
        return NextResponse.json(
          { error: `Unknown action: ${action}` },
          { status: 400 }
        );
    }
  } catch (error: any) {
    console.error('[FHE API] Error:', error);
    return NextResponse.json(
      { error: error.message || 'Internal FHE error' },
      { status: 500 }
    );
  }
}

function findActiveSession() {
  const now = Date.now();
  for (const [, session] of sessions.entries()) {
    if (session.expiry > now) return session;
  }
  return null;
}
