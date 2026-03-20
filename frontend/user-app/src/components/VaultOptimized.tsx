import React, { useState, useCallback, useMemo } from 'react';
import { useWriteContract } from 'wagmi';
import { useWallet } from '../hooks/useWallet';
import { useNotifications } from '../contexts/NotificationContext';
import { useDemoWallet } from '../hooks/useDemoWallet';
import { CONTRACT_ADDRESSES, formatUsdt, formatWad, parseUsdt, WAD, getContractAddresses } from '../config/contracts';
import { LEVER_VAULT_ABI, USDT_ABI, FEE_ROUTER_ABI, OI_LIMITS_ABI } from '../config/abis';
import { useRealAPY } from '../hooks/useRealAPY';
import { useVaultMulticall } from '../hooks/useVaultMulticall';
import { useMemoizedVaultCalculations } from '../hooks/useMemoizedCalculations';
import Skeleton from './Skeleton';
import VaultStats from './vault/VaultStats';
import TestnetDisclaimer from './TestnetDisclaimer';

const VaultOptimized: React.FC = () => {
  const { address, isDemoMode } = useWallet();
  const { showErrorToast, showSuccessToast } = useNotifications();
  const { sendTransaction: demoSend } = useDemoWallet();
  const [depositAmount, setDepositAmount] = useState('');
  const [withdrawShares, setWithdrawShares] = useState('');

  const { writeContract: depositToVault } = useWriteContract();
  const { writeContract: approveUsdt } = useWriteContract();
  const { writeContract: requestWithdrawal } = useWriteContract();

  // Vault multicall hook with fallback values for failed RPC calls
  const vaultData = useVaultMulticall(address);

  // CRITICAL FIX: Ensure vaultData is never undefined by providing robust fallback
  const safeVaultData = useMemo(() => {
    if (!vaultData) {
      console.warn('=== VAULT DATA IS UNDEFINED - Creating safe fallback ===');
      return {
        totalAssets: BigInt("250000000000"), // $250k TVL
        totalSupply: BigInt("250000000000000000000000"), // 250k shares
        sharePrice: BigInt("1000000000000000000"), // $1.00 per share
        globalOI: BigInt("50000000000"), // $50k OI
        userShares: BigInt("0"),
        usdtBalance: BigInt("0"),
        isLoadingVaultData: false,
        isLoadingUserData: false,
        hasError: true,
        errors: [{ message: 'Vault data hook returned undefined - using complete fallbacks', code: 'UNDEFINED_HOOK_RETURN' }],
        circuitBreakerOpen: false,
      };
    }
    return vaultData;
  }, [vaultData]);

  // Debug vault data received in component
  if (safeVaultData?.hasError || !safeVaultData?.totalAssets || safeVaultData?.totalAssets === BigInt(0)) {
    console.log('=== VAULT COMPONENT DEBUG (Error/No Data) ===', {
      originalVaultData: !!safeVaultData,
      safeVaultData,
      totalAssets: safeVaultData?.totalAssets?.toString(),
      totalSupply: safeVaultData?.totalSupply?.toString(),
      sharePrice: safeVaultData?.sharePrice?.toString(),
      globalOI: safeVaultData?.globalOI?.toString(),
      isLoading: safeVaultData?.isLoadingVaultData,
      hasError: safeVaultData?.hasError,
      errors: safeVaultData?.errors?.map(e => e.message),
      contractAddress: "0x84a1Eb3b1eFD60b193b271DCfaB2711cE1c41921",
      usingFallbacks: safeVaultData?.totalAssets?.toString() === "250000000000"
    });
  }

  // Memoized calculations - expensive computations only run when data changes
  const metrics = useMemoizedVaultCalculations({

    totalAssets: safeVaultData.totalAssets,
    totalSupply: safeVaultData.totalSupply,
    sharePrice: safeVaultData.sharePrice, // Pass direct sharePrice from convertToAssets
    borrowFees: BigInt(0), // Not available in new hook, use defaults
    transactionFees: BigInt(0),
    liquidationFees: BigInt(0),
    settlementFees: BigInt(0),
    globalOI: safeVaultData.globalOI,
    userShares: safeVaultData.userShares,
    usdtBalance: safeVaultData.usdtBalance,
  });
  const { apyPercent } = useRealAPY(safeVaultData.totalAssets);

  // Use share price directly from useVaultMulticall (comes from convertToAssets call)
  const sharePrice = useMemo(() => {
    try {
      // Enhanced debugging and validation
      console.log('=== SHARE PRICE DIRECT FROM VAULT DATA ===', {
        hasVaultData: !!safeVaultData,
        rawSharePrice: safeVaultData.sharePrice?.toString(),
        isLoading: safeVaultData.isLoadingVaultData,
        hasError: safeVaultData.hasError,
        errors: safeVaultData.errors?.map(e => e.message),
      });

      // If loading or no data, return fallback
      if (!safeVaultData || safeVaultData.isLoadingVaultData) {
        console.log('Vault data is loading, using fallback share price $1.00');
        return 1.0;
      }

      // If no sharePrice or zero, return fallback
      if (!safeVaultData.sharePrice || safeVaultData.sharePrice === BigInt(0)) {
        console.warn('No share price from safeVaultData, using fallback $1.00', {
          sharePrice: safeVaultData.sharePrice?.toString(),
          hasError: safeVaultData.hasError,
        });
        return 1.0; // Professional fallback
      }

      // FIXED: safeVaultData.sharePrice comes from convertToAssets(WAD) and is in WAD format
      // convertToAssets returns the amount of assets that would be received for 1 share (WAD = 1e18)
      // The result is in WAD format (18 decimals), so we need to convert from WAD to float
      const sharePriceFloat = Number(safeVaultData.sharePrice) / 1e18; // Convert WAD (18 decimals) to float

      console.log('=== SHARE PRICE DIRECT CALCULATION ===', {
        rawSharePrice: safeVaultData.sharePrice.toString(),
        sharePriceFloat,
        isValid: isFinite(sharePriceFloat) && sharePriceFloat > 0,
        errorCount: safeVaultData.errors?.length || 0,
      });

      // Validate the calculated share price
      if (!isFinite(sharePriceFloat) || sharePriceFloat <= 0 || isNaN(sharePriceFloat)) {
        console.warn('Invalid share price from safeVaultData.sharePrice, using fallback:', {
          rawValue: safeVaultData.sharePrice.toString(),
          calculatedFloat: sharePriceFloat,
          isFinite: isFinite(sharePriceFloat),
          isPositive: sharePriceFloat > 0,
          isNaN: isNaN(sharePriceFloat),
        });
        return 1.0; // Fallback to $1.00
      }

      return sharePriceFloat;
    } catch (error) {
      console.error('Error processing share price from safeVaultData, using fallback:', error, {
        safeVaultDataSharePrice: safeVaultData?.sharePrice?.toString(),
        hasVaultData: !!safeVaultData,
      });
      return 1.0; // Fallback on any error
    }
  }, [safeVaultData]);

  // Memoized form calculations using correct share price
  const formCalculations = useMemo(() => {
    const depositAmountFloat = parseFloat(depositAmount) || 0;
    const withdrawSharesFloat = parseFloat(withdrawShares) || 0;

    const sharesFromDeposit = sharePrice > 0
      ? depositAmountFloat / sharePrice
      : 0;

    const usdtFromWithdraw = withdrawSharesFloat * sharePrice;

    const dailyYieldFromDeposit = (depositAmountFloat * metrics.dailyYield) / 100;

    return {
      sharesFromDeposit,
      usdtFromWithdraw,
      dailyYieldFromDeposit,
    };
  }, [depositAmount, withdrawShares, sharePrice, metrics.dailyYield]);

  // Memoized event handlers
  const handleApprove = useCallback(async () => {
    if (!depositAmount) return;

    try {
      const amount = parseUsdt(depositAmount);
      if (isDemoMode) {
        await demoSend({
          address: CONTRACT_ADDRESSES.usdt,
          abi: USDT_ABI,
          functionName: 'approve',
          args: [CONTRACT_ADDRESSES.leverVault, amount],
        });
        showSuccessToast('USDT Approved', 'You can now deposit into the vault.');
      } else {
        await approveUsdt({
          address: CONTRACT_ADDRESSES.usdt,
          abi: USDT_ABI,
          functionName: 'approve',
          args: [CONTRACT_ADDRESSES.leverVault, amount],
        });
      }
    } catch (error: any) {
      console.error('Approval failed:', error);
      showErrorToast('Approve Failed', error?.shortMessage || error?.message || 'Unknown error');
    }
  }, [depositAmount, approveUsdt, isDemoMode, demoSend]);

  const handleDeposit = useCallback(async () => {
    if (!depositAmount || !address) return;

    try {
      const assets = parseUsdt(depositAmount);
      if (isDemoMode) {
        await demoSend({
          address: CONTRACT_ADDRESSES.leverVault,
          abi: LEVER_VAULT_ABI,
          functionName: 'deposit',
          args: [assets, address],
        });
        showSuccessToast('Deposit Successful', `Deposited ${depositAmount} USDT into the vault.`);
      } else {
        await depositToVault({
          address: CONTRACT_ADDRESSES.leverVault,
          abi: LEVER_VAULT_ABI,
          functionName: 'deposit',
          args: [assets, address],
        });
      }
    } catch (error: any) {
      console.error('Deposit failed:', error);
      showErrorToast('Deposit Failed', error?.shortMessage || error?.message || 'Unknown error');
    }
  }, [depositAmount, address, depositToVault, isDemoMode, demoSend]);

  const handleRequestWithdrawal = useCallback(async () => {
    if (!withdrawShares) return;

    try {
      const shares = BigInt(Math.floor(parseFloat(withdrawShares) * 1e6));
      if (isDemoMode) {
        await demoSend({
          address: CONTRACT_ADDRESSES.leverVault,
          abi: LEVER_VAULT_ABI,
          functionName: 'requestWithdrawal',
          args: [shares],
        });
      } else {
        await requestWithdrawal({
          address: CONTRACT_ADDRESSES.leverVault,
          abi: LEVER_VAULT_ABI,
          functionName: 'requestWithdrawal',
          args: [shares],
        });
      }
    } catch (error: any) {
      console.error('Withdrawal request failed:', error);
      showErrorToast('Withdrawal Failed', error?.shortMessage || error?.message || 'Unknown error');
    }
  }, [withdrawShares, requestWithdrawal, isDemoMode, demoSend]);

  // Memoized max deposit/withdraw helpers
  const setMaxDeposit = useCallback(() => {
    if (safeVaultData.usdtBalance) {
      setDepositAmount(formatUsdt(safeVaultData.usdtBalance));
    }
  }, [safeVaultData.usdtBalance]);

  const setMaxWithdraw = useCallback(() => {
    if (safeVaultData.userShares) {
      setWithdrawShares(formatUsdt(safeVaultData.userShares));
    }
  }, [safeVaultData.userShares]);

  // Component render
  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-gray-100">Liquidity Vault</h2>
        <p className="text-gray-500">
          Deposit USDT to earn yield from trading fees, funding payments, and borrow fees
        </p>
      </div>

      {/* Testnet Notice */}
      <TestnetDisclaimer compact={true} context="vault" />

      {/* Vault Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <VaultStats
          tvl={metrics.tvl}
          sharePrice={sharePrice}
          utilization={metrics.utilization}
          annualizedAPY={apyPercent || metrics.annualizedAPY}
          isLoading={safeVaultData.isLoadingVaultData}
          hasError={safeVaultData.hasError}
        />
      </div>

      {/* User Position */}
      {address && (
        <div className="bg-surface-2 rounded-lg border border-purple/20 p-6 shadow-glow-purple">
          <h3 className="text-lg font-semibold text-gray-100 mb-4">Your Position</h3>
          {safeVaultData.isLoadingUserData ? (
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              {[1, 2, 3].map((index) => (
                <div key={index}>
                  <Skeleton width="80px" height="16px" className="mb-2" />
                  <Skeleton width="120px" height="24px" />
                </div>
              ))}
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              <div>
                <p className="text-xs text-gray-500 uppercase tracking-wide">Your Shares</p>
                <p className="text-xl font-bold font-mono text-gray-100">
                  {metrics.userPosition.shares.toFixed(4)} lvUSDT
                </p>
              </div>
              <div>
                <p className="text-xs text-gray-500 uppercase tracking-wide">Value</p>
                <p className="text-xl font-bold font-mono text-gray-100">
                  ${metrics.userPosition.value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} USDT
                </p>
              </div>
              <div>
                <p className="text-xs text-gray-500 uppercase tracking-wide">Est. Daily Yield</p>
                <p className="text-xl font-bold font-mono text-accent">
                  ${(metrics.userPosition.value * metrics.dailyYield / 100).toFixed(2)}
                </p>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Deposit/Withdraw Interface */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Deposit */}
        <div className="bg-surface-1 rounded-lg border border-border p-6">
          <h3 className="text-lg font-semibold text-gray-100 mb-4">Deposit USDT</h3>

          <div className="space-y-4">
            <div>
              <div className="flex justify-between items-center mb-2">
                <label className="text-sm font-medium text-gray-400">
                  Amount (USDT)
                </label>
                <button
                  onClick={setMaxDeposit}
                  className="text-xs text-accent hover:text-accent-dim transition-colors"
                >
                  MAX
                </button>
              </div>
              <input
                type="number"
                step="0.01"
                min="0"
                value={depositAmount}
                onChange={(e) => setDepositAmount(e.target.value)}
                placeholder="0.00"
                className="w-full rounded-md bg-surface-3 border-border text-gray-200 shadow-sm focus:border-accent focus:ring-accent/30 font-mono"
              />
              <p className="text-xs text-gray-500 mt-1">
                Wallet Balance: {safeVaultData.isLoadingUserData ? (
                  <Skeleton width="60px" height="16px" className="inline-block" />
                ) : (
                  <span className="font-mono text-gray-400">{metrics.userBalance.formatted} USDT</span>
                )}
              </p>
            </div>

            {depositAmount && (
              <div className="bg-surface-2 rounded p-3 space-y-2">
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">You will receive:</span>
                  <span className="font-medium font-mono text-gray-200">
                    {formCalculations.sharesFromDeposit.toFixed(4)} lvUSDT
                  </span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">Est. daily yield:</span>
                  <span className="font-medium font-mono text-accent">
                    ${formCalculations.dailyYieldFromDeposit.toFixed(2)}
                  </span>
                </div>
              </div>
            )}

            <div className="space-y-2">
              <button
                onClick={handleApprove}
                disabled={!depositAmount}
                className="w-full bg-accent text-surface-0 py-2.5 px-4 rounded-md font-semibold hover:bg-accent-dim disabled:opacity-30 transition-colors"
              >
                1. Approve USDT
              </button>
              <button
                onClick={handleDeposit}
                disabled={!depositAmount || !address}
                className="w-full bg-purple text-white py-2.5 px-4 rounded-md font-semibold hover:bg-purple-dim disabled:opacity-30 transition-colors"
              >
                2. Deposit
              </button>
            </div>
          </div>
        </div>

        {/* Withdraw */}
        <div className="bg-surface-1 rounded-lg border border-border p-6">
          <h3 className="text-lg font-semibold text-gray-100 mb-4">Request Withdrawal</h3>

          <div className="space-y-4">
            <div>
              <div className="flex justify-between items-center mb-2">
                <label className="text-sm font-medium text-gray-400">
                  Shares to Withdraw
                </label>
                <button
                  onClick={setMaxWithdraw}
                  className="text-xs text-accent hover:text-accent-dim transition-colors"
                >
                  MAX
                </button>
              </div>
              <input
                type="number"
                step="0.0001"
                min="0"
                value={withdrawShares}
                onChange={(e) => setWithdrawShares(e.target.value)}
                placeholder="0.0000"
                className="w-full rounded-md bg-surface-3 border-border text-gray-200 shadow-sm focus:border-accent focus:ring-accent/30 font-mono"
              />
              <p className="text-xs text-gray-500 mt-1">
                Available: {safeVaultData.isLoadingUserData ? (
                  <Skeleton width="60px" height="16px" className="inline-block" />
                ) : (
                  <span className="font-mono text-gray-400">{metrics.userPosition.shares.toFixed(4)} lvUSDT</span>
                )}
              </p>
            </div>

            {withdrawShares && (
              <div className="bg-surface-2 rounded p-3 space-y-2">
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">You will receive:</span>
                  <span className="font-medium font-mono text-gray-200">
                    ${formCalculations.usdtFromWithdraw.toFixed(2)} USDT
                  </span>
                </div>
                <div className="flex justify-between text-xs">
                  <span className="text-gray-600">After 48h cooldown</span>
                  <span className="text-gray-600">At current NAV</span>
                </div>
              </div>
            )}

            <button
              onClick={handleRequestWithdrawal}
              disabled={!withdrawShares || parseFloat(withdrawShares) > metrics.userPosition.shares}
              className="w-full bg-danger/80 text-white py-2.5 px-4 rounded-md font-semibold hover:bg-danger disabled:opacity-30 transition-colors"
            >
              Request Withdrawal
            </button>
          </div>
        </div>
      </div>

      {/* Error/Info Display */}
      {safeVaultData.hasError && (
        <div className="bg-warning/10 border border-warning/20 text-warning rounded-lg p-4">
          <h4 className="font-semibold mb-2">Using Fallback Vault Data</h4>
          <p className="text-sm mb-2">
            RPC connection issues detected. Showing fallback values while reconnecting...
          </p>
          <p className="text-xs text-warning/70">
            Contract: {getContractAddresses().leverVault} | Error: {safeVaultData.errors[0]?.message || 'Unknown RPC error'}
          </p>
        </div>
      )}

      {/* Loading Indicator when vault is loading */}
      {safeVaultData.isLoadingVaultData && (
        <div className="bg-accent/10 border border-accent/20 text-accent rounded-lg p-4">
          <h4 className="font-semibold mb-2">Loading Vault Data...</h4>
          <p className="text-sm">
            Fetching live data from LeverVault contract...
          </p>
        </div>
      )}
    </div>
  );
};

export default VaultOptimized;