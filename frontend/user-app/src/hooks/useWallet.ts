import { usePrivy } from '@privy-io/react-auth';
import { useAccount } from 'wagmi';

/**
 * Custom hook that bridges Privy authentication with wagmi account state
 * Provides a consistent interface for wallet connection status and address
 */
export const useWallet = () => {
  const { authenticated, ready } = usePrivy();
  const { address, isConnected } = useAccount();

  return {
    // Use Privy's authenticated state as the primary source of truth for connection
    isConnected: authenticated,
    // Use wagmi's address when connected (Privy integrates with wagmi)
    address: authenticated ? address : undefined,
    // Include ready state for proper loading handling
    ready,
    // Legacy compatibility
    authenticated,
  };
};