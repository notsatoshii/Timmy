import { connectorsForWallets } from '@rainbow-me/rainbowkit';
import { injectedWallet } from '@rainbow-me/rainbowkit/wallets';
import { createConfig, http } from 'wagmi';
import { baseSepolia } from 'wagmi/chains';

// Only injected wallets — no WalletConnect, no external SDK dependencies
// injectedWallet covers MetaMask, Coinbase Wallet, Rabby, and any browser extension
const connectors = connectorsForWallets(
  [
    {
      groupName: 'Browser Wallets',
      wallets: [injectedWallet],
    },
  ],
  {
    appName: 'LEVER Protocol',
    projectId: 'NONE', // Not used — WalletConnect removed
  }
);

export const config = createConfig({
  connectors,
  chains: [baseSepolia],
  transports: {
    [baseSepolia.id]: http(),
  },
});

export { baseSepolia };
