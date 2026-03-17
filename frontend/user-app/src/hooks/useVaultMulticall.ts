import { useReadContract } from 'wagmi';
import { useMemo, useCallback } from 'react';
import { CONTRACT_ADDRESSES, WAD, getContractAddresses, loadContractAddresses } from '../config/contracts';
import { LEVER_VAULT_ABI, USDT_ABI, OI_LIMITS_ABI, BORROW_FEE_ENGINE_ABI } from '../config/abis';
import { useContractData, useContractReadEnhanced } from './useContractData';

/**
 * Enhanced vault multicall hook with comprehensive error handling and address loading
 * Automatically loads latest contract addresses and provides robust fallback values
 */
export function useVaultMulticall(userAddress?: `0x${string}`) {
  // Load contract addresses dynamically to ensure we have the latest addresses
  const contracts = useMemo(() => getContractAddresses(), []);

  // Comprehensive error handler with detailed logging
  const handleContractError = useCallback((error: any, context: string) => {
    console.error(`Vault data error [${context}]:`, {
      message: error.message,
      code: error.code,
      isNetworkError: error.isNetworkError,
      isRateLimit: error.isRateLimit,
      contractAddress: error.contractAddress,
      context,
    });

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

  // Enhanced vault data reading with error boundaries
  const totalAssetsRead = useContractReadEnhanced({
    address: contracts.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'totalAssets',
    name: 'TotalAssets',
    fallbackValue: fallbackValues.totalAssets,
    onError: (error) => handleContractError(error, 'totalAssets'),
  });

  const totalSupplyRead = useContractReadEnhanced({
    address: contracts.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'totalSupply',
    name: 'TotalSupply',
    fallbackValue: fallbackValues.totalSupply,
    onError: (error) => handleContractError(error, 'totalSupply'),
  });

  // Read share price using ERC-4626 standard convertToAssets
  const sharePriceRead = useContractReadEnhanced({
    address: contracts.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'convertToAssets',
    args: [WAD], // 1e18 = 1 share in WAD format
    name: 'SharePrice',
    fallbackValue: fallbackValues.sharePrice,
    onError: (error) => handleContractError(error, 'sharePrice'),
  });

  const globalOIRead = useContractReadEnhanced({
    address: contracts.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getGlobalOI',
    name: 'GlobalOI',
    fallbackValue: fallbackValues.globalOI,
    onError: (error) => handleContractError(error, 'globalOI'),
  });

  // User-specific data (only if address provided)
  const userSharesRead = useContractReadEnhanced({
    address: contracts.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'balanceOf',
    args: userAddress ? [userAddress] : undefined,
    name: 'UserShares',
    fallbackValue: fallbackValues.userShares,
    enabled: !!userAddress,
    onError: (error) => handleContractError(error, 'userShares'),
  });

  const usdtBalanceRead = useContractReadEnhanced({
    address: contracts.usdt,
    abi: USDT_ABI,
    functionName: 'balanceOf',
    args: userAddress ? [userAddress] : undefined,
    name: 'UsdtBalance',
    fallbackValue: fallbackValues.usdtBalance,
    enabled: !!userAddress,
    onError: (error) => handleContractError(error, 'usdtBalance'),
  });

  // Process and return comprehensive data
  return useMemo(() => {
    // Safe data extraction with guaranteed fallbacks
    const safeValues = {
      totalAssets: totalAssetsRead.data || fallbackValues.totalAssets,
      totalSupply: totalSupplyRead.data || fallbackValues.totalSupply,
      sharePrice: sharePriceRead.data || fallbackValues.sharePrice,
      globalOI: globalOIRead.data || fallbackValues.globalOI,
      userShares: userSharesRead.data || fallbackValues.userShares,
      usdtBalance: usdtBalanceRead.data || fallbackValues.usdtBalance,
    };

    // Loading states
    const isLoadingVaultData = (
      totalAssetsRead.isLoading ||
      totalSupplyRead.isLoading ||
      sharePriceRead.isLoading ||
      globalOIRead.isLoading
    );

    const isLoadingUserData = userAddress && (
      userSharesRead.isLoading ||
      usdtBalanceRead.isLoading
    );

    // Error collection and analysis
    const errors = [
      totalAssetsRead.error,
      totalSupplyRead.error,
      sharePriceRead.error,
      globalOIRead.error,
      userSharesRead.error,
      usdtBalanceRead.error,
    ].filter(Boolean);

    const hasError = errors.length > 0;
    const hasNetworkError = errors.some(e => e && e.isNetworkError);
    const hasRateLimit = errors.some(e => e && e.isRateLimit);

    // Enhanced error reporting
    if (hasError) {
      console.warn('Vault multicall has errors:', {
        errorCount: errors.length,
        hasNetworkError,
        hasRateLimit,
        errors: errors.filter((e): e is NonNullable<typeof e> => !!e).map(e => ({ message: e.message, code: e.code, contract: e.contractAddress })),
        fallbacksUsed: true,
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
    };
  }, [
    totalAssetsRead,
    totalSupplyRead,
    sharePriceRead,
    globalOIRead,
    userSharesRead,
    usdtBalanceRead,
    userAddress,
    fallbackValues,
  ]);
}