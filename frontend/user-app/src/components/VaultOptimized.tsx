import React, { useState, useCallback, useMemo } from 'react';
import { useAccount, useWriteContract } from 'wagmi';
import { CONTRACT_ADDRESSES, formatUsdt, formatWad, parseUsdt, WAD } from '../config/contracts';
import { LEVER_VAULT_ABI, USDT_ABI, FEE_ROUTER_ABI, OI_LIMITS_ABI } from '../config/abis';
import { useVaultMulticall } from '../hooks/useMulticall';
import { useMemoizedVaultCalculations } from '../hooks/useMemoizedCalculations';
import Skeleton from './Skeleton';

const VaultOptimized: React.FC = () => {
  const { address } = useAccount();
  const [depositAmount, setDepositAmount] = useState('');
  const [withdrawShares, setWithdrawShares] = useState('');

  const { writeContract: depositToVault } = useWriteContract();
  const { writeContract: approveUsdt } = useWriteContract();
  const { writeContract: requestWithdrawal } = useWriteContract();

  // Multicall hook - batches all contract reads into a single call
  const vaultData = useVaultMulticall(
    CONTRACT_ADDRESSES.leverVault,
    CONTRACT_ADDRESSES.feeRouter,
    CONTRACT_ADDRESSES.oiLimits,
    CONTRACT_ADDRESSES.usdt,
    LEVER_VAULT_ABI,
    FEE_ROUTER_ABI,
    OI_LIMITS_ABI,
    USDT_ABI,
    address
  );

  // Memoized calculations - expensive computations only run when data changes
  const metrics = useMemoizedVaultCalculations({
    totalAssets: vaultData.totalAssets,
    totalSupply: vaultData.totalSupply,
    borrowFees: vaultData.borrowFees,
    transactionFees: vaultData.transactionFees,
    liquidationFees: vaultData.liquidationFees,
    settlementFees: vaultData.settlementFees,
    globalOI: vaultData.globalOI,
    userShares: vaultData.userShares,
    usdtBalance: vaultData.usdtBalance,
  });

  // Memoized form calculations
  const formCalculations = useMemo(() => {
    const depositAmountFloat = parseFloat(depositAmount) || 0;
    const withdrawSharesFloat = parseFloat(withdrawShares) || 0;

    const sharesFromDeposit = metrics.sharePrice > 0
      ? depositAmountFloat / metrics.sharePrice
      : 0;

    const usdtFromWithdraw = withdrawSharesFloat * metrics.sharePrice;

    const dailyYieldFromDeposit = (depositAmountFloat * metrics.dailyYield) / 100;

    return {
      sharesFromDeposit,
      usdtFromWithdraw,
      dailyYieldFromDeposit,
    };
  }, [depositAmount, withdrawShares, metrics.sharePrice, metrics.dailyYield]);

  // Memoized event handlers
  const handleApprove = useCallback(async () => {
    if (!depositAmount) return;

    try {
      const amount = parseUsdt(depositAmount);
      await approveUsdt({
        address: CONTRACT_ADDRESSES.usdt,
        abi: USDT_ABI,
        functionName: 'approve',
        args: [CONTRACT_ADDRESSES.leverVault, amount],
      });
    } catch (error) {
      console.error('Approval failed:', error);
    }
  }, [depositAmount, approveUsdt]);

  const handleDeposit = useCallback(async () => {
    if (!depositAmount || !address) return;

    try {
      const assets = parseUsdt(depositAmount);
      await depositToVault({
        address: CONTRACT_ADDRESSES.leverVault,
        abi: LEVER_VAULT_ABI,
        functionName: 'deposit',
        args: [assets, address],
      });
    } catch (error) {
      console.error('Deposit failed:', error);
    }
  }, [depositAmount, address, depositToVault]);

  const handleRequestWithdrawal = useCallback(async () => {
    if (!withdrawShares) return;

    try {
      const shares = BigInt(Math.floor(parseFloat(withdrawShares) * 1e18));
      await requestWithdrawal({
        address: CONTRACT_ADDRESSES.leverVault,
        abi: LEVER_VAULT_ABI,
        functionName: 'requestWithdrawal',
        args: [shares],
      });
    } catch (error) {
      console.error('Withdrawal request failed:', error);
    }
  }, [withdrawShares, requestWithdrawal]);

  // Memoized max deposit/withdraw helpers
  const setMaxDeposit = useCallback(() => {
    if (vaultData.usdtBalance) {
      setDepositAmount(formatUsdt(vaultData.usdtBalance));
    }
  }, [vaultData.usdtBalance]);

  const setMaxWithdraw = useCallback(() => {
    if (vaultData.userShares) {
      setWithdrawShares(formatWad(vaultData.userShares));
    }
  }, [vaultData.userShares]);

  // Component render
  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-gray-100">Liquidity Vault</h2>
        <p className="text-gray-500">
          Deposit USDT to earn yield from trading fees, funding payments, and borrow fees
        </p>
      </div>

      {/* Vault Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        {vaultData.isLoadingVaultData ? (
          <>
            {[1, 2, 3, 4].map((index) => (
              <div key={index} className="bg-surface-1 rounded-lg border border-border p-6">
                <Skeleton width="120px" height="16px" className="mb-2" />
                <Skeleton width="80px" height="32px" className="mb-1" />
                <Skeleton width="60px" height="16px" />
              </div>
            ))}
          </>
        ) : (
          <>
            <div className="bg-surface-1 rounded-lg border border-border p-6">
              <h3 className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">Total Value Locked</h3>
              <p className="text-2xl font-bold font-mono text-gray-100">
                ${metrics.tvl.toLocaleString('en-US', { maximumFractionDigits: 0 })}
              </p>
              <p className="text-xs text-gray-600 mt-1">USDT</p>
            </div>

            <div className="bg-surface-1 rounded-lg border border-accent/20 p-6 shadow-glow-green">
              <h3 className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">Current APY</h3>
              <p className="text-3xl font-bold font-mono text-accent">
                {metrics.annualizedAPY.toFixed(1)}%
              </p>
              <p className="text-xs text-gray-600 mt-1">From trading fees</p>
            </div>

            <div className="bg-surface-1 rounded-lg border border-border p-6">
              <h3 className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">Vault Utilization</h3>
              <p className="text-2xl font-bold font-mono text-gray-100">
                {metrics.utilization.toFixed(1)}%
              </p>
              <div className="mt-2 h-1.5 bg-surface-3 rounded-full overflow-hidden">
                <div
                  className="h-full bg-accent rounded-full transition-all duration-500"
                  style={{ width: `${Math.min(100, metrics.utilization)}%` }}
                />
              </div>
            </div>

            <div className="bg-surface-1 rounded-lg border border-border p-6">
              <h3 className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">Share Price</h3>
              <p className="text-2xl font-bold font-mono text-gray-100">
                ${metrics.sharePrice.toFixed(4)}
              </p>
              <p className="text-xs text-gray-600 mt-1">lvUSDT per share</p>
            </div>
          </>
        )}
      </div>

      {/* User Position */}
      {address && (
        <div className="bg-surface-2 rounded-lg border border-purple/20 p-6 shadow-glow-purple">
          <h3 className="text-lg font-semibold text-gray-100 mb-4">Your Position</h3>
          {vaultData.isLoadingUserData ? (
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
                Wallet Balance: {vaultData.isLoadingUserData ? (
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
                Available: {vaultData.isLoadingUserData ? (
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

      {/* Error Display */}
      {vaultData.hasError && (
        <div className="bg-danger/10 border border-danger/20 text-danger rounded-lg p-4">
          <h4 className="font-semibold mb-2">Error Loading Vault Data</h4>
          <p className="text-sm">
            {vaultData.errors[0]?.message || 'Unknown error occurred'}
          </p>
        </div>
      )}
    </div>
  );
};

export default VaultOptimized;