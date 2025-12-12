'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';

export default function WalletConnect() {
  return (
    <div className="flex justify-end p-4">
      <ConnectButton
        accountStatus="address"
        chainStatus="icon"
        showBalance={true}
      />
    </div>
  );
}
