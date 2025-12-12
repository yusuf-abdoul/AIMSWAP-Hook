# AIMHook Frontend

Privacy-preserving swap interface for AIMHook on Uniswap v4 using Fhenix FHE.

## Quick Start

```bash
# Install dependencies
npm install

# Copy environment file
cp .env.example .env.local

# Update .env.local with your contract addresses

# Run development server
npm run dev

# Open http://localhost:3000
```

## Features

- 🔒 **Client-Side FHE Encryption** - Amounts encrypted using Fhenix SDK
- 🔍 **Intent Matching UI** - Submit private swap intents
- 💱 **P2P Settlement** - Direct peer-to-peer swaps when matched
- 🔄 **AMM Fallback** - Automatic fallback if no match found
- ⚡ **Real-time Status** - Track intent matching and settlement

## Environment Variables

Create `.env.local` with:

```env
NEXT_PUBLIC_POOL_MANAGER=<PoolManager address>
NEXT_PUBLIC_AIM_HOOK=<AIMHook address>
NEXT_PUBLIC_TOKEN0=<Token0 address>
NEXT_PUBLIC_TOKEN1=<Token1 address>
```

## How It Works

1. **User Input**: Enter swap amount and minimum return
2. **Encryption**: Fhenix SDK encrypts values client-side
3. **Submit**: Transaction sent to PoolManager with encrypted hookData
4. **Matching**: AIMHook searches for opposite direction intents
5. **Settlement**: If match → P2P transfer, else → AMM swap

## Project Structure

```
frontend/
├── app/
│   └── page.tsx          # Main landing page
├── components/
│   └── SwapIntent.tsx    # Swap interface component
├── .env.example          # Environment template
└── package.json          # Dependencies
```

## Integration with AIMHook

This frontend integrates with the AIMHook contracts:

- `script/EncryptIntent.ts` - Encryption logic (used by component)
- `script/KeeperBot.ts` - Keeper bot for settlement (run separately)
- `src/AIMHook.sol` - Main hook contract

## Dependencies

- **@fhenixprotocol/fhenix.js** - FHE encryption SDK
- **ethers** - Ethereum library
- **wagmi** - React hooks for Ethereum
- **Next.js** - React framework
- **TailwindCSS** - Styling

## Development

```bash
# Run dev server
npm run dev

# Build for production
npm run build

# Start production server
npm start
```

## Deployment

### Vercel (Recommended)

```bash
vercel deploy
```

### Docker

```bash
docker build -t aimhook-frontend .
docker run -p 3000:3000 aimhook-frontend
```

## Testing

Before using:

1. Deploy AIMHook contracts to Fhenix testnet
2. Update `.env.local` with contract addresses
3. Ensure wallet has testnet tokens
4. Approve hook contract to spend tokens

## Security Notes

- All encryption happens client-side
- Private keys never leave your browser
- Encrypted values stored on-chain
- Decryption requires proper permissions

## Support

- Docs: [USAGE_GUIDE.md](../USAGE_GUIDE.md)
- Contracts: [../src/](../src/)
- Issues: GitHub Issues

---

**Note**: This is an MVP interface. For production:
- Add proper error handling
- Implement wallet connection UI
- Add transaction history
- Show pending intents
- Display matched pairs
- Add permit management
