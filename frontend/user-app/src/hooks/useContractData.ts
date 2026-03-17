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
        });

        // More conservative retry logic for rate limiting
        if (failureCount < retryAttempts) {
          if (enhanced.isRateLimit) {
            // Only retry rate limits once to avoid hammering
            return failureCount === 0;
          }
          if (enhanced.isNetworkError) {
            return true;
          }
        }
        return false;
      },
      retryDelay: (attemptIndex, error) => {
        const enhanced = enhanceError(error);

        // Much longer delays for rate limiting
        if (enhanced.isRateLimit) {
          const rateLimit Delay = Math.min(10000 * Math.pow(2, attemptIndex), 60000); // 10s, 20s, 40s, 60s max
          const jitter = Math.random() * 2000; // More jitter for rate limits
          console.log(`Rate limit retry delay: ${rateLimitDelay + jitter}ms`);
          return rateLimitDelay + jitter;
        }

        // Normal exponential backoff with jitter for other errors
        const baseDelay = Math.min(1000 * Math.pow(2, attemptIndex), 15000);
        const jitter = Math.random() * 500;
        return baseDelay + jitter;
      },
      staleTime: 15000, // 15s
      refetchInterval: 30000, // 30s
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

        console.warn(`Contract read failed (attempt ${failureCount + 1}):`, {
          name: name || functionName,
          address,
          error: enhanced.message,
          code: enhanced.code,
          isNetworkError: enhanced.isNetworkError,
          isRateLimit: enhanced.isRateLimit,
        });

        if (failureCount < 3) {
          if (enhanced.isNetworkError || enhanced.isRateLimit) {
            return true;
          }
        }
        return false;
      },
      retryDelay: (attemptIndex) => {
        const baseDelay = Math.min(1000 * Math.pow(2, attemptIndex), 30000);
        const jitter = Math.random() * 1000;
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

  // Rate limiting (413 and similar)
  enhanced.isRateLimit = (
    enhanced.code === 413 ||
    enhanced.code === 429 ||
    message.includes('rate limit') ||
    message.includes('too many requests') ||
    message.includes('throttled')
  );

  return enhanced;
}

export default useContractData;