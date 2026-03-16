import { createConfig, http } from 'wagmi';
import { baseSepolia } from 'wagmi/chains';
import { injected, metaMask, coinbaseWallet } from 'wagmi/connectors';

export const config = createConfig({
  chains: [baseSepolia],
  connectors: [
    injected(),
    metaMask({ dappMetadata: { name: 'LEVER Protocol' } }),
    coinbaseWallet({ appName: 'LEVER Protocol' }),
  ],
  transports: {
    [baseSepolia.id]: http(),
  },
});

export { baseSepolia };
