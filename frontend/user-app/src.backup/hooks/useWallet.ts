import { useAccount } from 'wagmi';
import { useDemo } from '../contexts/DemoContext';

/**
 * Custom hook providing consistent wallet connection state.
 * Supports both real wallet connections and demo mode.
 */
export const useWallet = () => {
  const { address, isConnected } = useAccount();
  const { isDemoMode, demoAddress } = useDemo();

  // In demo mode, simulate wallet connection
  const walletAddress = isDemoMode ? demoAddress : address;
  const walletConnected = isDemoMode ? true : isConnected;

  return {
    isConnected: walletConnected,
    address: walletConnected ? (walletAddress as `0x${string}`) : undefined,
    ready: true,
    authenticated: walletConnected,
    isDemoMode,
  };
};
