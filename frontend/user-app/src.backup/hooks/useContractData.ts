import { useReadContract, useReadContracts } from 'wagmi';
import { useMemo, useEffect, useCallback } from 'react';

// Enhanced error types for better debugging
interface ContractDataError extends Error {
  code?: string | number;
  cause?: Error;
  isNetworkError?: boolean;
  isRateLimit?: boolean;
  contractAddress?: string;
  functionName?: string;
}

interface ContractCall {
  address: `0x${string}`;
  abi: any;
  functionName: string;
  args?: any[];
  name?: string; // For debugging
}

interface ContractDataConfig {
  contracts: ContractCall[];
  enabled?: boolean;
  fallbackValues?: Record<string, any>;
  onError?: (error: ContractDataError, callIndex: number) => void;
  retryAttempts?: number;
}

/**
 * Enhanced contract data hook with comprehensive error handling and logging
 * Provides detailed error boundaries and automatic fallback for failed RPC calls
 */
export function useContractData(config: ContractDataConfig) {
  const {
    contracts,
    enabled = true,
    fallbackValues = {},
    onError,
    retryAttempts = 3
  } = config;

  // Use wagmi's multicall for efficiency
  const result = useReadContracts({
    contracts: contracts.map(contract => ({
      address: contract.address,
      abi: contract.abi,
      functionName: contract.functionName,
      args: contract.args,
    })),
    query: {
      enabled,
      retry: (failureCount, error) => {
        const enhanced = enhanceError(error);

        // Log all errors for debugging
        console.warn(`Contract multicall failed (attempt ${failureCount + 1}/${retryAttempts}):`, {
          error: enhanced.message,
          code: enhanced.code,
          isNetworkError: enhanced.isNetworkError,
          isRateLimit: enhanced.isRateLimit,
          contracts: contracts.map(c => ({ address: c.address, function: c.functionName })),
          failureCount: failureCount + 1,
          timestamp: new Date().toISOString(),
        });

        // Enhanced retry logic with exponential backoff consideration
        if (failureCount < retryAttempts) {
          if (enhanced.isRateLimit) {
            // Allow up to 2 retries for rate limits with exponential backoff
            return failureCount < 2;
          }
          if (enhanced.isNetworkError) {
            // Allow all retries for network errors
            return true;
          }
          // Allow retries for other errors but be more conservative
          return failureCount < Math.min(2, retryAttempts);
        }
        return false;
      },
      retryDelay: (attemptIndex, error) => {
        const enhanced = enhanceError(error);

        // Enhanced exponential backoff for rate limiting
        if (enhanced.isRateLimit) {
          // More aggressive backoff for 413 errors: 5s, 20s, 80s
          const rateLimitDelay = Math.min(5000 * Math.pow(4, attemptIndex), 120000);
          const jitter = Math.random() * 3000; // 0-3s jitter
          console.log(`Rate limit retry delay (attempt ${attemptIndex + 1}): ${Math.ceil((rateLimitDelay + jitter) / 1000)}s`);
          return rateLimitDelay + jitter;
        }

        // Enhanced exponential backoff for network errors: 2s, 8s, 32s
        if (enhanced.isNetworkError) {
          const networkDelay = Math.min(2000 * Math.pow(4, attemptIndex), 60000);
          const jitter = Math.random() * 1000;
          console.log(`Network error retry delay (attempt ${attemptIndex + 1}): ${Math.ceil((networkDelay + jitter) / 1000)}s`);
          return networkDelay + jitter;
        }

        // Standard exponential backoff for other errors: 1s, 4s, 16s
        const baseDelay = Math.min(1000 * Math.pow(4, attemptIndex), 30000);
        const jitter = Math.random() * 500;
        return baseDelay + jitter;
      },
      staleTime: 20000, // 20s - slightly longer to reduce pressure
      refetchInterval: 45000, // 45s - longer interval to reduce rate limiting
    },
  });

  // Enhanced error handling with detailed logging
  useEffect(() => {
    if (result.error || (result.data && result.data.some(r => r.status === 'failure'))) {
      // Global error
      if (result.error) {
        const enhanced = enhanceError(result.error);
        console.error('Multicall failed completely:', {
          error: enhanced.message,
          code: enhanced.code,
          isNetworkError: enhanced.isNetworkError,
          isRateLimit: enhanced.isRateLimit,
          contracts: contracts.length
        });

        if (onError) {
          onError(enhanced, -1);
        }
      }

      // Individual call errors
      if (result.data) {
        result.data.forEach((callResult, index) => {
          if (callResult.status === 'failure') {
            const enhanced = enhanceError(callResult.error, contracts[index]);
            console.error(`Contract call failed [${index}]:`, {
              name: contracts[index]?.name || 'unknown',
              address: contracts[index]?.address,
              function: contracts[index]?.functionName,
              error: enhanced.message,
              code: enhanced.code,
              isNetworkError: enhanced.isNetworkError,
              isRateLimit: enhanced.isRateLimit,
            });

            if (onError) {
              onError(enhanced, index);
            }
          }
        });
      }
    }
  }, [result.error, result.data, contracts, onError]);

  // Process results with fallbacks
  const processedData = useMemo(() => {
    if (!result.data) {
      return {
        data: contracts.map((contract, index) =>
          fallbackValues[contract.name || contract.functionName] || null
        ),
        isLoading: result.isLoading,
        errors: result.error ? [enhanceError(result.error)] : [],
        hasError: !!result.error,
        hasNetworkError: result.error ? enhanceError(result.error).isNetworkError : false,
        hasRateLimit: result.error ? enhanceError(result.error).isRateLimit : false,
      };
    }

    const data = result.data.map((callResult, index) => {
      if (callResult.status === 'success') {
        return callResult.result;
      } else {
        // Use fallback value for failed calls
        const fallbackKey = contracts[index]?.name || contracts[index]?.functionName;
        return fallbackValues[fallbackKey] || null;
      }
    });

    const errors = result.data
      .map((callResult, index) =>
        callResult.status === 'failure'
          ? enhanceError(callResult.error, contracts[index])
          : null
      )
      .filter(Boolean) as ContractDataError[];

    const hasNetworkError = errors.some(e => e.isNetworkError);
    const hasRateLimit = errors.some(e => e.isRateLimit);

    return {
      data,
      isLoading: result.isLoading,
      errors,
      hasError: errors.length > 0,
      hasNetworkError,
      hasRateLimit,
    };
  }, [result.data, result.error, result.isLoading, contracts, fallbackValues]);

  return processedData;
}

/**
 * Single contract read with enhanced error handling
 */
export function useContractReadEnhanced({
  address,
  abi,
  functionName,
  args,
  name,
  fallbackValue,
  enabled = true,
  onError,
}: {
  address: `0x${string}`;
  abi: any;
  functionName: string;
  args?: any[];
  name?: string;
  fallbackValue?: any;
  enabled?: boolean;
  onError?: (error: ContractDataError) => void;
}) {
  const result = useReadContract({
    address,
    abi,
    functionName,
    args,
    query: {
      enabled,
      retry: (failureCount, error) => {
        const enhanced = enhanceError(error, { address, functionName, name });

        console.warn(`Contract read failed (attempt ${failureCount + 1}/3):`, {
          name: name || functionName,
          address,
          error: enhanced.message,
          code: enhanced.code,
          isNetworkError: enhanced.isNetworkError,
          isRateLimit: enhanced.isRateLimit,
          timestamp: new Date().toISOString(),
        });

        // Enhanced retry logic with better exponential backoff
        if (failureCount < 3) {
          if (enhanced.isRateLimit) {
            // Allow 2 retries for rate limits with long delays
            return failureCount < 2;
          }
          if (enhanced.isNetworkError) {
            return true;
          }
          // Allow retries for other contract errors
          return failureCount < 2;
        }
        return false;
      },
      retryDelay: (attemptIndex, error) => {
        const enhanced = enhanceError(error, { address, functionName, name });

        // Enhanced exponential backoff for rate limiting
        if (enhanced.isRateLimit) {
          const rateLimitDelay = Math.min(6000 * Math.pow(4, attemptIndex), 90000); // 6s, 24s, 96s
          const jitter = Math.random() * 2500; // 0-2.5s jitter
          console.log(`Single contract rate limit retry delay (attempt ${attemptIndex + 1}): ${Math.ceil((rateLimitDelay + jitter) / 1000)}s`);
          return rateLimitDelay + jitter;
        }

        // Enhanced exponential backoff for network errors
        if (enhanced.isNetworkError) {
          const networkDelay = Math.min(2500 * Math.pow(3, attemptIndex), 45000); // 2.5s, 7.5s, 22.5s
          const jitter = Math.random() * 1000;
          return networkDelay + jitter;
        }

        // Standard exponential backoff for other errors
        const baseDelay = Math.min(1500 * Math.pow(3, attemptIndex), 25000);
        const jitter = Math.random() * 750;
        return baseDelay + jitter;
      },
    },
  });

  // Error handling
  useEffect(() => {
    if (result.error && onError) {
      const enhanced = enhanceError(result.error, { address, functionName, name });
      onError(enhanced);
    }
  }, [result.error, onError, address, functionName, name]);

  return useMemo(() => ({
    data: result.data ?? fallbackValue,
    isLoading: result.isLoading,
    error: result.error ? enhanceError(result.error, { address, functionName, name }) : null,
    hasError: !!result.error,
    isNetworkError: result.error ? enhanceError(result.error).isNetworkError : false,
    isRateLimit: result.error ? enhanceError(result.error).isRateLimit : false,
  }), [result.data, result.isLoading, result.error, fallbackValue, address, functionName, name]);
}

/**
 * Enhanced error with additional context and type detection
 */
function enhanceError(error: any, context?: { address?: string; functionName?: string; name?: string }): ContractDataError {
  if (!error) return {} as ContractDataError;

  const enhanced = new Error(error.message || 'Unknown contract error') as ContractDataError;
  enhanced.code = error.code;
  enhanced.cause = error;
  enhanced.name = error.name || 'ContractDataError';

  // Add context
  if (context) {
    enhanced.contractAddress = context.address;
    enhanced.functionName = context.functionName;
    enhanced.message = `${context.name || context.functionName || 'Contract'}: ${enhanced.message}`;
  }

  // Detect error types
  const message = enhanced.message?.toLowerCase() || '';

  // Network errors
  enhanced.isNetworkError = (
    message.includes('network') ||
    message.includes('fetch') ||
    message.includes('timeout') ||
    message.includes('connection') ||
    message.includes('cors') ||
    enhanced.code === 'NETWORK_ERROR' ||
    enhanced.code === 'TIMEOUT' ||
    enhanced.code === -32603 ||
    enhanced.code === 'ECONNRESET'
  );

  // Rate limiting (413 and similar) - enhanced detection
  enhanced.isRateLimit = (
    enhanced.code === 413 ||
    enhanced.code === 429 ||
    enhanced.code === '413' ||
    enhanced.code === '429' ||
    message.includes('413') ||
    message.includes('429') ||
    message.includes('rate limit') ||
    message.includes('too many requests') ||
    message.includes('throttled') ||
    message.includes('quota exceeded') ||
    message.includes('request limit') ||
    message.includes('payload too large') ||
    message.includes('entity too large') ||
    // RPC specific rate limiting responses
    message.includes('exceeded') ||
    (enhanced.code === -32005) || // RPC rate limit code
    (enhanced.code === -32000 && message.includes('limit'))
  );

  return enhanced;
}

export default useContractData;