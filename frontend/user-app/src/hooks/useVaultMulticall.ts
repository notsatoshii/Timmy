import { useReadContract } from 'wagmi';
import { useMemo, useCallback, useState, useEffect, useRef } from 'react';
import { CONTRACT_ADDRESSES, WAD, getContractAddresses, loadContractAddresses } from '../config/contracts';
import { LEVER_VAULT_ABI, USDT_ABI, OI_LIMITS_ABI, BORROW_FEE_ENGINE_ABI } from '../config/abis';
import { useContractData, useContractReadEnhanced } from './useContractData';

/**
 * Circuit breaker state for rate limiting
 */
interface CircuitBreakerState {
  isOpen: boolean;
  failureCount: number;
  lastFailure: number;
  nextAttemptTime: number;
}

const CIRCUIT_BREAKER_KEY = 'rpc_circuit_breaker';
const MAX_FAILURES = 3;
const CIRCUIT_OPEN_DURATION = 30000; // 30 seconds
const FAILURE_RESET_TIME = 60000; // Reset failure count after 60 seconds

function getCircuitBreakerState(): CircuitBreakerState {
  const stored = localStorage.getItem(CIRCUIT_BREAKER_KEY);
  if (stored) {
    const state = JSON.parse(stored) as CircuitBreakerState;
    // Reset if enough time has passed
    if (Date.now() - state.lastFailure > FAILURE_RESET_TIME) {
      return { isOpen: false, failureCount: 0, lastFailure: 0, nextAttemptTime: 0 };
    }
    return state;
  }
  return { isOpen: false, failureCount: 0, lastFailure: 0, nextAttemptTime: 0 };
}

function updateCircuitBreakerState(state: CircuitBreakerState) {
  localStorage.setItem(CIRCUIT_BREAKER_KEY, JSON.stringify(state));
}

/**
 * Enhanced vault multicall hook with 413 error handling, exponential backoff, and circuit breaker
 * Uses single multicall for efficiency and rate limit avoidance
 * Implements fallback values when RPC fails to prevent $NaN displays
 */
export function useVaultMulticall(userAddress?: `0x${string}`) {
  // Circuit breaker state
  const [circuitBreaker, setCircuitBreaker] = useState<CircuitBreakerState>(getCircuitBreakerState);
  const retriesRef = useRef<number>(0);
  const lastRetryTimeRef = useRef<number>(0);

  // Load contract addresses dynamically to ensure we have the latest addresses
  const contracts = useMemo(() => getContractAddresses(), []);

  // Enhanced error handler with exponential backoff and circuit breaker for 413 errors
  const handleContractError = useCallback((error: any, context: string, callIndex: number = -1) => {
    const isRateLimit = error?.code === 413 || error?.code === 429 ||
                       error?.message?.toLowerCase().includes('413') ||
                       error?.message?.toLowerCase().includes('rate limit') ||
                       error?.message?.toLowerCase().includes('too many requests') ||
                       error?.message?.toLowerCase().includes('entity too large') ||
                       error?.message?.toLowerCase().includes('payload too large');

    const isNetworkError = error?.message?.toLowerCase().includes('network') ||
                          error?.message?.toLowerCase().includes('fetch') ||
                          error?.message?.toLowerCase().includes('timeout') ||
                          error?.code === 'NETWORK_ERROR';

    console.error(`Vault data error [${context}]:`, {
      message: error.message,
      code: error.code,
      isNetworkError: error.isNetworkError || isNetworkError,
      isRateLimit,
      contractAddress: error.contractAddress,
      context,
      callIndex,
      timestamp: new Date().toISOString(),
    });

    // Handle rate limiting with enhanced exponential backoff
    if (isRateLimit) {
      const currentState = getCircuitBreakerState();
      const newFailureCount = currentState.failureCount + 1;
      const now = Date.now();

      // Exponential backoff with jitter (3 attempts: 2s, 8s, 32s)
      const baseDelay = Math.min(2000 * Math.pow(4, newFailureCount - 1), 60000); // 2s, 8s, 32s, max 60s
      const jitter = Math.random() * 1000; // 0-1s jitter to avoid thundering herd
      const backoffDelay = baseDelay + jitter;

      const newState: CircuitBreakerState = {
        failureCount: newFailureCount,
        lastFailure: now,
        isOpen: newFailureCount >= MAX_FAILURES,
        nextAttemptTime: newFailureCount >= MAX_FAILURES ? now + backoffDelay : now + Math.min(backoffDelay / 2, 5000),
      };

      updateCircuitBreakerState(newState);
      setCircuitBreaker(newState);
      lastRetryTimeRef.current = now;

      console.warn(`Rate limit detected (${newFailureCount}/${MAX_FAILURES}). Circuit breaker ${newState.isOpen ? 'OPENED' : 'monitoring'}. Next attempt in ${Math.ceil(backoffDelay / 1000)}s`);
    }

    // Enhanced retry tracking for other network errors
    if (isNetworkError && !isRateLimit) {
      retriesRef.current = Math.min(retriesRef.current + 1, 5);
      console.warn(`Network error detected. Retry count: ${retriesRef.current}/3`);
    }

    // Attempt to reload addresses if we have contract-not-found errors
    if (error.message?.includes('missing revert data') ||
        error.message?.includes('contract not responding') ||
        error.message?.includes('call revert exception')) {
      console.warn('Attempting to reload contract addresses due to contract errors');
      loadContractAddresses().then(() => {
        console.log('Contract addresses reloaded');
      }).catch(err => {
        console.error('Failed to reload contract addresses:', err);
      });
    }
  }, []);

  // Fallback values for failed calls - CRITICAL for preventing NaN displays
  const fallbackValues = useMemo(() => {
    // Safe BigInt construction with error handling
    const createSafeBigInt = (value: string, description: string): bigint => {
      try {
        const result = BigInt(value);
        if (result < 0) {
          console.warn(`Negative fallback value for ${description}, using 0`);
          return BigInt(0);
        }
        return result;
      } catch (error) {
        console.error(`Failed to create BigInt for ${description}:`, error);
        return BigInt(0);
      }
    };

    return {
      totalAssets: createSafeBigInt("50000000000", "totalAssets"), // $50,000 in USDT format (6 decimals)
      totalSupply: createSafeBigInt("50000000000000000000000", "totalSupply"), // 50,000 shares in WAD format (18 decimals)
      sharePrice: createSafeBigInt("1000000000000000000", "sharePrice"), // $1.00 in WAD format (18 decimals)
      globalOI: createSafeBigInt("0", "globalOI"),
      userShares: createSafeBigInt("0", "userShares"),
      usdtBalance: createSafeBigInt("0", "usdtBalance"),
    };
  }, []);

  // Circuit breaker check
  useEffect(() => {
    const checkCircuitBreaker = () => {
      const currentState = getCircuitBreakerState();
      if (currentState.isOpen && Date.now() > currentState.nextAttemptTime) {
        // Circuit breaker should close
        const resetState: CircuitBreakerState = {
          isOpen: false,
          failureCount: 0,
          lastFailure: 0,
          nextAttemptTime: 0,
        };
        updateCircuitBreakerState(resetState);
        setCircuitBreaker(resetState);
        console.log('Circuit breaker CLOSED - resuming requests');
      }
    };

    const interval = setInterval(checkCircuitBreaker, 5000);
    return () => clearInterval(interval);
  }, []);

  // Split contract calls into smaller batches (max 5 calls each) to avoid 413 errors
  const contractBatches = useMemo(() => {
    // Batch 1: Core vault data (4 calls)
    const coreVaultCalls = [
      {
        address: contracts.leverVault,
        abi: LEVER_VAULT_ABI,
        functionName: 'totalAssets',
        name: 'TotalAssets'
      },
      {
        address: contracts.leverVault,
        abi: LEVER_VAULT_ABI,
        functionName: 'totalSupply',
        name: 'TotalSupply'
      },
      {
        address: contracts.leverVault,
        abi: LEVER_VAULT_ABI,
        functionName: 'convertToAssets',
        args: [WAD],
        name: 'SharePrice'
      },
      {
        address: contracts.oiLimits,
        abi: OI_LIMITS_ABI,
        functionName: 'getGlobalOI',
        name: 'GlobalOI'
      }
    ];

    // Batch 2: User-specific data (2 calls) - only if address is provided
    const userDataCalls = userAddress ? [
      {
        address: contracts.leverVault,
        abi: LEVER_VAULT_ABI,
        functionName: 'balanceOf',
        args: [userAddress] as any,
        name: 'UserShares'
      },
      {
        address: contracts.usdt,
        abi: USDT_ABI as any,
        functionName: 'balanceOf',
        args: [userAddress] as any,
        name: 'UsdtBalance'
      }
    ] : [];

    return {
      coreVaultCalls,
      userDataCalls,
    };
  }, [contracts, userAddress]);

  // TEMPORARY FIX: Disable circuit breaker to debug vault data issues
  const isCircuitBreakerDisabled = true;

  // Batch 1: Core vault multicall with enhanced retry logic
  const coreMulticallResult = useContractData({
    contracts: contractBatches.coreVaultCalls,
    enabled: isCircuitBreakerDisabled || !circuitBreaker.isOpen,
    fallbackValues: {
      TotalAssets: fallbackValues.totalAssets,
      TotalSupply: fallbackValues.totalSupply,
      SharePrice: fallbackValues.sharePrice,
      GlobalOI: fallbackValues.globalOI,
    },
    onError: (error, callIndex) => handleContractError(error, contractBatches.coreVaultCalls[callIndex]?.name || `core-call-${callIndex}`, callIndex),
    retryAttempts: isCircuitBreakerDisabled ? 3 : (circuitBreaker.isOpen ? 0 : Math.max(1, 3 - circuitBreaker.failureCount)),
  });

  // Batch 2: User data multicall with enhanced retry logic
  const userMulticallResult = useContractData({
    contracts: contractBatches.userDataCalls,
    enabled: (isCircuitBreakerDisabled || !circuitBreaker.isOpen) && !!userAddress && contractBatches.userDataCalls.length > 0,
    fallbackValues: {
      UserShares: fallbackValues.userShares,
      UsdtBalance: fallbackValues.usdtBalance,
    },
    onError: (error, callIndex) => handleContractError(error, contractBatches.userDataCalls[callIndex]?.name || `user-call-${callIndex}`, callIndex),
    retryAttempts: isCircuitBreakerDisabled ? 3 : (circuitBreaker.isOpen ? 0 : Math.max(1, 3 - circuitBreaker.failureCount)),
  });

  // Process and return comprehensive data from batched multicalls
  return useMemo(() => {
    // Enhanced debugging for vault data issues
    console.log('=== VAULT MULTICALL DEBUG ===', {
      circuitBreakerOpen: circuitBreaker.isOpen,
      coreMulticallResult: {
        data: coreMulticallResult?.data,
        isLoading: coreMulticallResult?.isLoading,
        errors: coreMulticallResult?.errors?.map(e => e.message),
        hasError: coreMulticallResult?.hasError,
      },
      userMulticallResult: {
        data: userMulticallResult?.data,
        isLoading: userMulticallResult?.isLoading,
        errors: userMulticallResult?.errors?.map(e => e.message),
        hasError: userMulticallResult?.hasError,
      },
      contractAddresses: contracts,
      fallbackValues,
    });

    // If circuit breaker is open, return fallback values (DISABLED FOR DEBUGGING)
    if (!isCircuitBreakerDisabled && circuitBreaker.isOpen) {
      const timeUntilReset = Math.max(0, circuitBreaker.nextAttemptTime - Date.now());
      console.warn(`Circuit breaker is OPEN. Next attempt in ${Math.ceil(timeUntilReset / 1000)}s`);

      return {
        totalAssets: fallbackValues.totalAssets,
        totalSupply: fallbackValues.totalSupply,
        sharePrice: fallbackValues.sharePrice,
        globalOI: fallbackValues.globalOI,
        userShares: fallbackValues.userShares,
        usdtBalance: fallbackValues.usdtBalance,
        isLoadingVaultData: false,
        isLoadingUserData: false,
        hasError: true,
        hasNetworkError: false,
        hasRateLimit: true,
        errors: [{ message: 'Circuit breaker is open due to rate limiting', code: 'CIRCUIT_BREAKER_OPEN' }],
        circuitBreakerOpen: true,
        nextAttemptTime: circuitBreaker.nextAttemptTime,
      };
    }

    // Extract data from both batched results
    const coreData = coreMulticallResult?.data || [];
    const userData = userMulticallResult?.data || [];

    // Safely extract values with comprehensive BigInt validation and fallback handling
    const safeBigIntValue = (value: any, fallbackValue: bigint, name: string): bigint => {
      try {
        // Check for null/undefined
        if (value === null || value === undefined) {
          console.warn(`${name} is null/undefined, using fallback`);
          return fallbackValue;
        }

        // If it's already a BigInt, validate it
        if (typeof value === 'bigint') {
          if (value < 0) {
            console.warn(`${name} is negative (${value.toString()}), using fallback`);
            return fallbackValue;
          }
          return value;
        }

        // Try to convert to BigInt
        const bigintValue = BigInt(value);
        if (bigintValue < 0) {
          console.warn(`${name} converted to negative BigInt (${bigintValue.toString()}), using fallback`);
          return fallbackValue;
        }

        return bigintValue;
      } catch (error) {
        console.warn(`Failed to process ${name} value:`, error, 'Raw value:', value, 'Using fallback:', fallbackValue.toString());
        return fallbackValue;
      }
    };

    // Enhanced debugging for data extraction
    console.log('=== VAULT DATA EXTRACTION ===', {
      coreDataArray: coreData,
      coreDataLength: coreData?.length,
      coreDataValues: coreData?.map((val, idx) => ({ index: idx, value: val, type: typeof val })),
      userDataArray: userData,
      userDataLength: userData?.length,
      userDataValues: userData?.map((val, idx) => ({ index: idx, value: val, type: typeof val })),
    });

    const safeValues = {
      // Core vault data from batch 1
      totalAssets: safeBigIntValue(coreData[0], fallbackValues.totalAssets, 'totalAssets'),
      totalSupply: safeBigIntValue(coreData[1], fallbackValues.totalSupply, 'totalSupply'),
      sharePrice: safeBigIntValue(coreData[2], fallbackValues.sharePrice, 'sharePrice'),
      globalOI: safeBigIntValue(coreData[3], fallbackValues.globalOI, 'globalOI'),
      // User data from batch 2 (only if user address provided)
      userShares: userAddress ? safeBigIntValue(userData[0], fallbackValues.userShares, 'userShares') : fallbackValues.userShares,
      usdtBalance: userAddress ? safeBigIntValue(userData[1], fallbackValues.usdtBalance, 'usdtBalance') : fallbackValues.usdtBalance,
    };

    console.log('=== SAFE VALUES EXTRACTED ===', {
      totalAssets: safeValues.totalAssets.toString(),
      totalSupply: safeValues.totalSupply.toString(),
      sharePrice: safeValues.sharePrice.toString(),
      globalOI: safeValues.globalOI.toString(),
      userShares: safeValues.userShares.toString(),
      usdtBalance: safeValues.usdtBalance.toString(),
    });

    // Loading states - both batches must complete for vault data, user data depends on user batch only
    const isLoadingVaultData = (coreMulticallResult?.isLoading || false) && (isCircuitBreakerDisabled || !circuitBreaker.isOpen);
    const isLoadingUserData = userAddress ? ((userMulticallResult?.isLoading || false) && (isCircuitBreakerDisabled || !circuitBreaker.isOpen)) : false;

    // Comprehensive error analysis from both batches
    const coreErrors = coreMulticallResult?.errors || [];
    const userErrors = userMulticallResult?.errors || [];
    const allErrors = [...coreErrors, ...userErrors];

    const hasError = allErrors.length > 0 || circuitBreaker.isOpen;
    const hasNetworkError = (coreMulticallResult?.hasNetworkError || userMulticallResult?.hasNetworkError) || false;
    const hasRateLimit = (coreMulticallResult?.hasRateLimit || userMulticallResult?.hasRateLimit) || circuitBreaker.isOpen;

    // Enhanced error reporting with batch-aware logging
    if (hasError && !circuitBreaker.isOpen) {
      console.warn('Vault multicall batches have errors:', {
        coreErrors: coreErrors.length,
        userErrors: userErrors.length,
        totalErrors: allErrors.length,
        hasNetworkError,
        hasRateLimit,
        errors: allErrors.map(e => ({
          message: e.message,
          code: e.code,
          contract: e.contractAddress,
          isRateLimit: e.isRateLimit,
        })),
        fallbacksUsed: true,
        circuitBreakerFailures: circuitBreaker.failureCount,
        batchingActive: true,
      });
    }

    // Enhanced validation: ensure we got valid data for critical fields
    const validationErrors = [];
    const validationWarnings = [];

    // Validate critical values - allow fallback values but warn if they're being used
    if (safeValues.totalAssets === fallbackValues.totalAssets) {
      validationWarnings.push('Using fallback totalAssets ($50,000)');
    } else if (safeValues.totalAssets === BigInt(0)) {
      validationErrors.push('totalAssets is zero after validation');
    }

    if (safeValues.totalSupply === fallbackValues.totalSupply) {
      validationWarnings.push('Using fallback totalSupply (50,000 shares)');
    } else if (safeValues.totalSupply === BigInt(0)) {
      validationErrors.push('totalSupply is zero after validation');
    }

    if (safeValues.sharePrice === fallbackValues.sharePrice) {
      validationWarnings.push('Using fallback sharePrice ($1.00)');
    } else if (safeValues.sharePrice === BigInt(0)) {
      validationErrors.push('sharePrice is zero after validation');
    }

    // Log validation results
    if (validationErrors.length > 0) {
      console.error('Vault data validation errors:', validationErrors);
    }
    if (validationWarnings.length > 0) {
      console.warn('Vault data validation warnings (using fallbacks):', validationWarnings);
    }

    // Final safety check: ensure no undefined/null values made it through
    Object.entries(safeValues).forEach(([key, value]) => {
      if (value === null || value === undefined) {
        console.error(`CRITICAL: ${key} is still null/undefined after validation!`, value);
        (safeValues as any)[key] = (fallbackValues as any)[key] || BigInt(0);
      }
    });

    return {
      ...safeValues,
      isLoadingVaultData,
      isLoadingUserData,
      hasError,
      hasNetworkError,
      hasRateLimit,
      errors: allErrors,
      circuitBreakerOpen: circuitBreaker.isOpen,
      nextAttemptTime: circuitBreaker.nextAttemptTime,
      retryAttempts: retriesRef.current,
      batchingActive: true, // Flag to indicate batching is being used
      validationErrors,
    };
  }, [
    coreMulticallResult,
    userMulticallResult,
    userAddress,
    fallbackValues,
    circuitBreaker,
  ]);
}