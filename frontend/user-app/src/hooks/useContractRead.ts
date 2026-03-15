import { useReadContract } from 'wagmi';
import { useEffect } from 'react';

interface ContractReadOptions {
  address: `0x${string}`;
  abi: any;
  functionName: string;
  args?: any[];
  onError?: (error: Error) => void;
  enabled?: boolean;
}

/**
 * Enhanced useReadContract hook with better error handling
 * Provides additional error context and graceful degradation
 */
export function useContractReadSafe(options: ContractReadOptions) {
  const result = useReadContract({
    address: options.address,
    abi: options.abi,
    functionName: options.functionName,
    args: options.args,
    query: {
      enabled: options.enabled !== false,
      retry: (failureCount, error) => {
        // Retry up to 2 times for network errors
        // Don't retry for contract errors (like function doesn't exist)
        if (failureCount < 2 && isNetworkError(error)) {
          return true;
        }
        return false;
      },
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
    }
  });

  // Enhanced error handling
  useEffect(() => {
    if (result.error && options.onError) {
      const enhancedError = new Error(
        `Contract read failed for ${options.functionName}: ${result.error.message}`
      );
      enhancedError.cause = result.error;
      options.onError(enhancedError);
    }
  }, [result.error, options]);

  return {
    ...result,
    isContractError: result.error && !isNetworkError(result.error),
    isNetworkError: result.error && isNetworkError(result.error),
    errorMessage: formatErrorMessage(result.error),
  };
}

/**
 * Determine if an error is likely a network/connectivity issue
 */
function isNetworkError(error: any): boolean {
  if (!error) return false;

  const message = error.message?.toLowerCase() || '';
  const errorCode = error.code;

  // Common network error indicators
  return (
    message.includes('network') ||
    message.includes('fetch') ||
    message.includes('timeout') ||
    message.includes('connection') ||
    message.includes('cors') ||
    errorCode === 'NETWORK_ERROR' ||
    errorCode === 'TIMEOUT' ||
    errorCode === -32603 // Internal JSON-RPC error (often network)
  );
}

/**
 * Format error messages to be more user-friendly
 */
function formatErrorMessage(error: any): string | null {
  if (!error) return null;

  const message = error.message || 'Unknown error';

  // Contract-specific error formatting
  if (message.includes('execution reverted')) {
    return 'Contract call failed - this function may not be available or parameters may be invalid';
  }

  if (isNetworkError(error)) {
    return 'Network connection error - please check your internet connection and try again';
  }

  if (message.includes('missing revert data')) {
    return 'Contract not responding - the contract may not be deployed on this network';
  }

  if (message.includes('cannot estimate gas')) {
    return 'Transaction would fail - check contract state and parameters';
  }

  return message;
}

export default useContractReadSafe;