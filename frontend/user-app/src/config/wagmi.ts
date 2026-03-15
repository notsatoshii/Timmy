import { connectorsForWallets } from '@rainbow-me/rainbowkit';
import { injectedWallet, metaMaskWallet, coinbaseWallet } from '@rainbow-me/rainbowkit/wallets';
import { createConfig, http } from 'wagmi';
import { baseSepolia } from 'wagmi/chains';

// Only injected wallets — no WalletConnect, no WebSocket origin errors
const connectors = connectorsForWallets(
  [
    {
      groupName: 'Supported Wallets',
      wallets: [injectedWallet, metaMaskWallet, coinbaseWallet],
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
