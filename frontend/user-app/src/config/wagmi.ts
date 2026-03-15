import { createConfig, http } from 'wagmi';
import { baseSepolia } from 'wagmi/chains';
import { injected } from 'wagmi/connectors';

// Only injected connector — no WalletConnect, no WebSocket origin errors
// Covers MetaMask, Coinbase Wallet, Rabby, and any browser extension wallet
export const config = createConfig({
  chains: [baseSepolia],
  connectors: [injected()],
  transports: {
    [baseSepolia.id]: http(),
  },
});

export { baseSepolia };
