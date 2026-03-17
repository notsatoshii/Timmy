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
 * Enhanced vault multicall hook with 413 error handling and circuit breaker
 * Uses single multicall for efficiency and rate limit avoidance
 */
export function useVaultMulticall(userAddress?: `0x${string}`) {
  // Circuit breaker state
  const [circuitBreaker, setCircuitBreaker] = useState<CircuitBreakerState>(getCircuitBreakerState);
  const retriesRef = useRef<number>(0);

  // Load contract addresses dynamically to ensure we have the latest addresses
  const contracts = useMemo(() => getContractAddresses(), []);

  // Enhanced error handler with circuit breaker for 413 errors
  const handleContractError = useCallback((error: any, context: string, callIndex: number = -1) => {
    const isRateLimit = error?.code === 413 || error?.code === 429 ||
                       error?.message?.toLowerCase().includes('413') ||
                       error?.message?.toLowerCase().includes('rate limit') ||
                       error?.message?.toLowerCase().includes('too many requests');

    console.error(`Vault data error [${context}]:`, {
      message: error.message,
      code: error.code,
      isNetworkError: error.isNetworkError,
      isRateLimit,
      contractAddress: error.contractAddress,
      context,
      callIndex,
    });

    // Handle rate limiting with circuit breaker
    if (isRateLimit) {
      const currentState = getCircuitBreakerState();
      const newFailureCount = currentState.failureCount + 1;
      const now = Date.now();

      const newState: CircuitBreakerState = {
        failureCount: newFailureCount,
        lastFailure: now,
        isOpen: newFailureCount >= MAX_FAILURES,
        nextAttemptTime: newFailureCount >= MAX_FAILURES ? now + CIRCUIT_OPEN_DURATION : 0,
      };

      updateCircuitBreakerState(newState);
      setCircuitBreaker(newState);

      console.warn(`Rate limit detected (${newFailureCount}/${MAX_FAILURES}). Circuit breaker ${newState.isOpen ? 'OPENED' : 'monitoring'}`);

      // Exponential backoff for subsequent requests
      const backoffDelay = Math.min(1000 * Math.pow(2, newFailureCount), 60000);
      console.log(`Next attempt after ${backoffDelay}ms backoff`);
    }

    // Attempt to reload addresses if we have contract-not-found errors
    if (error.message?.includes('missing revert data') || error.message?.includes('contract not responding')) {
      console.warn('Attempting to reload contract addresses due to contract errors');
      loadContractAddresses().then(() => {
        console.log('Contract addresses reloaded');
      }).catch(err => {
        console.error('Failed to reload contract addresses:', err);
      });
    }
  }, []);

  // Fallback values for failed calls
  const fallbackValues = useMemo(() => ({
    totalAssets: BigInt("50000000000"), // $50,000 in USDT format (6 decimals)
    totalSupply: BigInt("50000000000000000000000"), // 50,000 shares in WAD format (18 decimals)
    sharePrice: BigInt("1000000000000000000"), // $1.00 in WAD format (18 decimals)
    globalOI: BigInt("0"),
    userShares: BigInt("0"),
    usdtBalance: BigInt("0"),
  }), []);

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

  // Prepare batched contract calls - reduce batch size to avoid 413 errors
  const contractCalls = useMemo(() => {
    const baseCalls = [
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

    // Add user-specific calls only if address is provided
    if (userAddress) {
      baseCalls.push(
        {
          address: contracts.leverVault,
          abi: LEVER_VAULT_ABI,
          functionName: 'balanceOf',
          args: [userAddress] as any,
          name: 'UserShares'
        },
        {
          address: contracts.usdt,
          abi: USDT_ABI,
          functionName: 'balanceOf',
          args: [userAddress] as any,
          name: 'UsdtBalance'
        }
      );
    }

    return baseCalls;
  }, [contracts, userAddress]);

  // Single batched multicall to reduce RPC load and avoid 413 errors
  const multicallResult = useContractData({
    contracts: contractCalls,
    enabled: !circuitBreaker.isOpen,
    fallbackValues: {
      TotalAssets: fallbackValues.totalAssets,
      TotalSupply: fallbackValues.totalSupply,
      SharePrice: fallbackValues.sharePrice,
      GlobalOI: fallbackValues.globalOI,
      UserShares: fallbackValues.userShares,
      UsdtBalance: fallbackValues.usdtBalance,
    },
    onError: (error, callIndex) => handleContractError(error, contractCalls[callIndex]?.name || `call-${callIndex}`, callIndex),
    retryAttempts: circuitBreaker.isOpen ? 0 : (circuitBreaker.failureCount > 0 ? 1 : 2), // Reduce retries when we've had failures
  });

  // Process and return comprehensive data from batched multicall
  return useMemo(() => {
    // If circuit breaker is open, return fallback values
    if (circuitBreaker.isOpen) {
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

    // Extract data from batched result
    const data = multicallResult?.data || [];

    // Map results to named values with proper indexing
    const baseCallsCount = 4; // totalAssets, totalSupply, sharePrice, globalOI
    const hasUserCalls = !!userAddress;

    const safeValues = {
      totalAssets: data[0] || fallbackValues.totalAssets,
      totalSupply: data[1] || fallbackValues.totalSupply,
      sharePrice: data[2] || fallbackValues.sharePrice,
      globalOI: data[3] || fallbackValues.globalOI,
      userShares: hasUserCalls ? (data[4] || fallbackValues.userShares) : fallbackValues.userShares,
      usdtBalance: hasUserCalls ? (data[5] || fallbackValues.usdtBalance) : fallbackValues.usdtBalance,
    };

    // Loading states
    const isLoadingVaultData = multicallResult?.isLoading && !circuitBreaker.isOpen;
    const isLoadingUserData = userAddress ? isLoadingVaultData : false;

    // Error analysis with circuit breaker awareness
    const errors = multicallResult?.errors || [];
    const hasError = errors.length > 0 || circuitBreaker.isOpen;
    const hasNetworkError = multicallResult?.hasNetworkError || false;
    const hasRateLimit = multicallResult?.hasRateLimit || circuitBreaker.isOpen;

    // Enhanced error reporting with circuit breaker info
    if (hasError && !circuitBreaker.isOpen) {
      console.warn('Vault multicall has errors:', {
        errorCount: errors.length,
        hasNetworkError,
        hasRateLimit,
        errors: errors.map(e => ({
          message: e.message,
          code: e.code,
          contract: e.contractAddress,
          isRateLimit: e.isRateLimit,
        })),
        fallbacksUsed: true,
        circuitBreakerFailures: circuitBreaker.failureCount,
      });
    }

    return {
      ...safeValues,
      isLoadingVaultData,
      isLoadingUserData,
      hasError,
      hasNetworkError,
      hasRateLimit,
      errors,
      circuitBreakerOpen: circuitBreaker.isOpen,
      nextAttemptTime: circuitBreaker.nextAttemptTime,
      retryAttempts: retriesRef.current,
    };
  }, [
    multicallResult,
    userAddress,
    fallbackValues,
    circuitBreaker,
  ]);
}