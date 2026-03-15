import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { baseSepolia } from 'wagmi/chains';

export const config = getDefaultConfig({
  appName: 'LEVER Protocol',
  projectId: 'YOUR_PROJECT_ID', // Get from WalletConnect
  chains: [baseSepolia],
  ssr: false,
});

export { baseSepolia };