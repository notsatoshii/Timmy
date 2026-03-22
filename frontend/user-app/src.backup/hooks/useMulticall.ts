import { useReadContracts } from 'wagmi';
import { useMemo } from 'react';

interface ContractCall {
  address: `0x${string}`;
  abi: any;
  functionName: string;
  args?: any[];
}

interface MulticallResult<T = any> {
  data: T | undefined;
  error: Error | null;
  isLoading: boolean;
}

interface MulticallConfig {
  contracts: ContractCall[];
  enabled?: boolean;
  query?: {
    refetchInterval?: number;
    staleTime?: number;
  };
}

/**
 * Enhanced multicall hook for batching multiple contract reads
 * Reduces network calls and improves performance by batching reads into a single call
 */
export function useMulticall(config: MulticallConfig): MulticallResult[] {
  const { contracts, enabled = true, query } = config;

  const result = useReadContracts({
    contracts: contracts.map((contract) => ({
      address: contract.address,
      abi: contract.abi,
      functionName: contract.functionName,
      args: contract.args,
    })),
    query: {
      enabled,
      refetchInterval: query?.refetchInterval,
      staleTime: query?.staleTime || 30000, // 30s stale time by default
      retry: (failureCount, error) => {
        // Retry up to 2 times for network errors
        if (failureCount < 2 && isNetworkError(error)) {
          return true;
        }
        return false;
      },
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30000),
    },
  });

  // Transform the result into individual results for each contract call
  return useMemo(() => {
    if (!result.data) {
      return contracts.map(() => ({
        data: undefined,
        error: result.error,
        isLoading: result.isLoading,
      }));
    }

    return result.data.map((callResult, index) => ({
      data: callResult.status === 'success' ? callResult.result : undefined,
      error: callResult.status === 'failure' ? callResult.error : null,
      isLoading: result.isLoading,
    }));
  }, [result.data, result.error, result.isLoading, contracts.length]);
}

/**
 * Specialized hook for vault data that batches common vault reads
 */
export function useVaultMulticall(
  vaultAddress: `0x${string}`,
  feeRouterAddress: `0x${string}`,
  oiLimitsAddress: `0x${string}`,
  usdtAddress: `0x${string}`,
  vaultAbi: any,
  feeRouterAbi: any,
  oiLimitsAbi: any,
  usdtAbi: any,
  userAddress?: `0x${string}`
) {
  const contracts: ContractCall[] = useMemo(() => {
    const baseContracts: ContractCall[] = [
      // Vault data
      { address: vaultAddress, abi: vaultAbi, functionName: 'totalAssets' },
      { address: vaultAddress, abi: vaultAbi, functionName: 'totalSupply' },

      // Fee data (4 fee types)
      { address: feeRouterAddress, abi: feeRouterAbi, functionName: 'getTotalFeesRouted', args: [0] },
      { address: feeRouterAddress, abi: feeRouterAbi, functionName: 'getTotalFeesRouted', args: [1] },
      { address: feeRouterAddress, abi: feeRouterAbi, functionName: 'getTotalFeesRouted', args: [2] },
      { address: feeRouterAddress, abi: feeRouterAbi, functionName: 'getTotalFeesRouted', args: [3] },

      // OI data
      { address: oiLimitsAddress, abi: oiLimitsAbi, functionName: 'getGlobalOI' },
    ];

    // Add user-specific calls if address provided
    if (userAddress) {
      baseContracts.push(
        { address: vaultAddress, abi: vaultAbi, functionName: 'balanceOf', args: [userAddress] },
        { address: usdtAddress, abi: usdtAbi, functionName: 'balanceOf', args: [userAddress] }
      );
    }

    return baseContracts;
  }, [vaultAddress, feeRouterAddress, oiLimitsAddress, usdtAddress, userAddress, vaultAbi, feeRouterAbi, oiLimitsAbi, usdtAbi]);

  const results = useMulticall({
    contracts,
    enabled: true,
    query: {
      refetchInterval: 30000, // Refresh every 30 seconds
      staleTime: 15000,       // Consider stale after 15 seconds
    }
  });

  // Parse results into named fields
  return useMemo(() => {
    const [
      totalAssets,
      totalSupply,
      borrowFees,
      transactionFees,
      liquidationFees,
      settlementFees,
      globalOI,
      userShares,
      usdtBalance,
    ] = results;

    return {
      // Vault stats
      totalAssets: totalAssets.data,
      totalSupply: totalSupply.data,
      globalOI: globalOI.data,

      // Fee data
      borrowFees: borrowFees.data,
      transactionFees: transactionFees.data,
      liquidationFees: liquidationFees.data,
      settlementFees: settlementFees.data,

      // User data (if address provided)
      userShares: userShares?.data,
      usdtBalance: usdtBalance?.data,

      // Loading states
      isLoading: results.some(r => r.isLoading),
      isLoadingVaultData: results.slice(0, 7).some(r => r.isLoading),
      isLoadingUserData: userAddress ? results.slice(7).some(r => r.isLoading) : false,

      // Errors
      errors: results.map(r => r.error).filter(Boolean),
      hasError: results.some(r => r.error),
    };
  }, [results, userAddress]);
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

export default useMulticall;