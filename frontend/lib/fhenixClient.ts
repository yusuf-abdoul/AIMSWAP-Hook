/**
 * @deprecated This file used the old fhenixjs library.
 * FHE operations now go through the server-side API route at /api/fhe
 * using cofhejs/node. See components/FhenixProvider.tsx for the new client.
 */

export function getFhenixClient(): null {
  console.warn('getFhenixClient() is deprecated. Use the FhenixProvider context instead.');
  return null;
}
