import '@rainbow-me/rainbowkit/styles.css';
import { Providers } from './providers';
import './globals.css';

export const metadata = {
  title: 'AIMHook - Private Swaps on Uniswap v4',
  description: 'Privacy-preserving CoW protocol using Fhenix FHE coprocessor',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
