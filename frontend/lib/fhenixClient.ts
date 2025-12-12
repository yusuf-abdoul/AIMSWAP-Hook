import { FhenixClient } from 'fhenixjs';

let fhenixClientInstance: FhenixClient | null = null;

export async function initFhenixClient(provider?: any): Promise<FhenixClient> {
  if (typeof window === 'undefined') {
    throw new Error('FhenixClient can only be initialized in browser environment');
  }

  if (fhenixClientInstance) {
    return fhenixClientInstance;
  }

  try {
    // Initialize FhenixClient with custom WASM path
    fhenixClientInstance = new FhenixClient({
      provider: provider || window.ethereum,
    });

    console.log('FhenixClient initialized successfully');
    return fhenixClientInstance;
  } catch (error) {
    console.error('Failed to initialize FhenixClient:', error);
    throw error;
  }
}

export function getFhenixClient(): FhenixClient | null {
  return fhenixClientInstance;
}
