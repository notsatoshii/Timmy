import { useAccount } from 'wagmi';

/**
 * Custom hook providing consistent wallet connection state.
 * Uses wagmi's useAccount as the single source of truth.
 */
export const useWallet = () => {
  const { address, isConnected } = useAccount();

  return {
    isConnected,
    address: isConnected ? address : undefined,
    ready: true,
    authenticated: isConnected,
  };
};
