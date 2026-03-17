import { useReadContract } from 'wagmi';
import { useMemo } from 'react';
import { CONTRACT_ADDRESSES, WAD } from '../config/contracts';
import { LEVER_VAULT_ABI, USDT_ABI, OI_LIMITS_ABI, BORROW_FEE_ENGINE_ABI } from '../config/abis';

/**
 * Specialized vault multicall hook with fallback values for failed RPC calls
 * Returns fallback values when RPC calls fail to prevent NaN calculations
 */
export function useVaultMulticall(userAddress?: `0x${string}`) {
  // Read vault stats with proper error handling
  const { data: totalAssets, isLoading: loadingTotalAssets, error: totalAssetsError } = useReadContract({
    address: CONTRACT_ADDRESSES.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'totalAssets',
  });

  const { data: totalShares, isLoading: loadingTotalShares, error: totalSharesError } = useReadContract({
    address: CONTRACT_ADDRESSES.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'totalSupply',
  });

  // Read share price using ERC-4626 standard convertToAssets
  const { data: rawSharePrice, isLoading: loadingSharePrice, error: sharePriceError } = useReadContract({
    address: CONTRACT_ADDRESSES.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'convertToAssets',
    args: [WAD], // 1e18 = 1 share in WAD format
  });

  const { data: userShares, isLoading: loadingUserShares, error: userSharesError } = useReadContract({
    address: CONTRACT_ADDRESSES.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'balanceOf',
    args: userAddress ? [userAddress] : undefined,
  });

  const { data: usdtBalance, isLoading: loadingUsdtBalance, error: usdtBalanceError } = useReadContract({
    address: CONTRACT_ADDRESSES.usdt,
    abi: USDT_ABI,
    functionName: 'balanceOf',
    args: userAddress ? [userAddress] : undefined,
  });

  const { data: globalOI, isLoading: loadingGlobalOI, error: globalOIError } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getGlobalOI',
  });

  // Compute vault data with fallbacks
  return useMemo(() => {
    // Provide fallback values when RPC calls fail OR when values are 0n (to prevent NaN)
    const safeValues = {
      sharePrice: rawSharePrice && !sharePriceError && rawSharePrice > BigInt("0")
        ? rawSharePrice
        : BigInt("1000000"), // $1.00 in USDT format (6 decimals)
      totalAssets: totalAssets && !totalAssetsError && totalAssets > BigInt("0")
        ? totalAssets
        : BigInt("50000000000"), // $50,000 in USDT format (6 decimals)
      totalSupply: totalShares && !totalSharesError && totalShares > BigInt("0")
        ? totalShares
        : BigInt("50000000000"), // 50,000 shares in USDT format (6 decimals)
      globalOI: globalOI && !globalOIError
        ? globalOI
        : BigInt("0"),
      userShares: userShares && !userSharesError
        ? userShares
        : BigInt("0"),
      usdtBalance: usdtBalance && !usdtBalanceError
        ? usdtBalance
        : BigInt("0"),
    };

    // Check for any loading state
    const isLoadingVaultData = loadingTotalAssets || loadingTotalShares || loadingSharePrice || loadingGlobalOI;
    const isLoadingUserData = userAddress && (loadingUserShares || loadingUsdtBalance);

    // Collect errors
    const errors = [
      totalAssetsError,
      totalSharesError,
      sharePriceError,
      globalOIError,
      userSharesError,
      usdtBalanceError,
    ].filter(Boolean);

    const hasError = errors.length > 0;

    return {
      ...safeValues,
      isLoadingVaultData,
      isLoadingUserData,
      hasError,
      errors,
    };
  }, [
    totalAssets, totalShares, rawSharePrice, globalOI, userShares, usdtBalance,
    totalAssetsError, totalSharesError, sharePriceError, globalOIError, userSharesError, usdtBalanceError,
    loadingTotalAssets, loadingTotalShares, loadingSharePrice, loadingGlobalOI, loadingUserShares, loadingUsdtBalance,
    userAddress
  ]);
}