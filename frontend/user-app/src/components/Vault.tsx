import React, { useState } from 'react';
import { useReadContract, useWriteContract } from 'wagmi';
import { useWallet } from '../hooks/useWallet';
import { CONTRACT_ADDRESSES, formatUsdt, formatWad, parseUsdt, WAD } from '../config/contracts';
import { LEVER_VAULT_ABI, USDT_ABI, FEE_ROUTER_ABI, OI_LIMITS_ABI } from '../config/abis';
import Skeleton from './Skeleton';

const Vault: React.FC = () => {
  const { address } = useWallet();
  const [depositAmount, setDepositAmount] = useState('');
  const [withdrawShares, setWithdrawShares] = useState('');

  const { writeContract: depositToVault } = useWriteContract();
  const { writeContract: approveUsdt } = useWriteContract();
  const { writeContract: requestWithdrawal } = useWriteContract();

  // Read vault stats
  const { data: totalAssets, isLoading: loadingTotalAssets } = useReadContract({
    address: CONTRACT_ADDRESSES.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'totalAssets',
  });

  const { data: totalShares, isLoading: loadingTotalShares } = useReadContract({
    address: CONTRACT_ADDRESSES.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'totalSupply',
  });

  const { data: userShares, isLoading: loadingUserShares } = useReadContract({
    address: CONTRACT_ADDRESSES.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
  });

  const { data: usdtBalance, isLoading: loadingUsdtBalance } = useReadContract({
    address: CONTRACT_ADDRESSES.usdt,
    abi: USDT_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
  });

  // Read fee data for APY calculation
  const { data: borrowFees, isLoading: loadingBorrowFees } = useReadContract({
    address: CONTRACT_ADDRESSES.feeRouter,
    abi: FEE_ROUTER_ABI,
    functionName: 'getTotalFeesRouted',
    args: [0],
  });

  const { data: transactionFees, isLoading: loadingTransactionFees } = useReadContract({
    address: CONTRACT_ADDRESSES.feeRouter,
    abi: FEE_ROUTER_ABI,
    functionName: 'getTotalFeesRouted',
    args: [1],
  });

  const { data: liquidationFees, isLoading: loadingLiquidationFees } = useReadContract({
    address: CONTRACT_ADDRESSES.feeRouter,
    abi: FEE_ROUTER_ABI,
    functionName: 'getTotalFeesRouted',
    args: [2],
  });

  const { data: settlementFees, isLoading: loadingSettlementFees } = useReadContract({
    address: CONTRACT_ADDRESSES.feeRouter,
    abi: FEE_ROUTER_ABI,
    functionName: 'getTotalFeesRouted',
    args: [3],
  });

  const { data: globalOI, isLoading: loadingGlobalOI } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getGlobalOI',
  });

  const isLoadingVaultData =
    loadingTotalAssets ||
    loadingTotalShares ||
    loadingBorrowFees ||
    loadingTransactionFees ||
    loadingLiquidationFees ||
    loadingSettlementFees ||
    loadingGlobalOI;

  const isLoadingUserData = address && (loadingUserShares || loadingUsdtBalance);

  const handleApprove = async () => {
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
      console.error('Error approving USDT:', error);
    }
  };

  const handleDeposit = async () => {
    if (!depositAmount) return;

    try {
      const amount = parseUsdt(depositAmount);
      await depositToVault({
        address: CONTRACT_ADDRESSES.leverVault,
        abi: LEVER_VAULT_ABI,
        functionName: 'deposit',
        args: [amount, address!],
      });
      setDepositAmount('');
    } catch (error) {
      console.error('Error depositing to vault:', error);
    }
  };

  const handleRequestWithdrawal = async () => {
    if (!withdrawShares || !userShares) return;

    try {
      const sharesToWithdraw = BigInt(Math.floor(parseFloat(withdrawShares) * 1e18));
      await requestWithdrawal({
        address: CONTRACT_ADDRESSES.leverVault,
        abi: LEVER_VAULT_ABI,
        functionName: 'requestWithdrawal',
        args: [sharesToWithdraw],
      });
      setWithdrawShares('');
    } catch (error) {
      console.error('Error requesting withdrawal:', error);
    }
  };

  const calculateShareValue = (): string => {
    if (!totalAssets || !totalShares || totalShares === BigInt(0)) return '1.00';
    return (Number(totalAssets) / Number(totalShares) / 1e12).toFixed(4);
  };

  const calculateUserAssets = (): string => {
    if (!userShares || !totalAssets || !totalShares || totalShares === BigInt(0)) return '0';
    const userAssetValue = (userShares * totalAssets) / totalShares;
    return formatUsdt(userAssetValue);
  };

  const getVaultUtilization = (): number => {
    if (!totalAssets || !globalOI || totalAssets === BigInt(0)) return 0;
    const tvlInWad = totalAssets * BigInt(1e12);
    const utilizationBps = Number(globalOI * BigInt(10000) / tvlInWad);
    return Math.min(100, utilizationBps / 100);
  };

  const calculateAPY = (): number => {
    if (!totalAssets || totalAssets === BigInt(0)) return 0;

    const totalFees =
      (borrowFees || BigInt(0)) +
      (transactionFees || BigInt(0)) +
      (liquidationFees || BigInt(0)) +
      (settlementFees || BigInt(0));

    if (totalFees === BigInt(0)) return 0;

    const lpShare = totalFees / BigInt(2);
    const annualReturn = Number(lpShare * BigInt(100)) / Number(totalAssets);

    return Math.min(999, annualReturn);
  };

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
        {isLoadingVaultData ? (
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
                ${totalAssets ? formatUsdt(totalAssets) : '0'}
              </p>
              <p className="text-xs text-gray-600 mt-1">USDT</p>
            </div>

            <div className="bg-surface-1 rounded-lg border border-accent/20 p-6 shadow-glow-green">
              <h3 className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">Current APY</h3>
              <p className="text-3xl font-bold font-mono text-accent">
                {calculateAPY().toFixed(1)}%
              </p>
              <p className="text-xs text-gray-600 mt-1">From trading fees</p>
            </div>

            <div className="bg-surface-1 rounded-lg border border-border p-6">
              <h3 className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">Vault Utilization</h3>
              <p className="text-2xl font-bold font-mono text-gray-100">
                {getVaultUtilization().toFixed(1)}%
              </p>
              <div className="mt-2 h-1.5 bg-surface-3 rounded-full overflow-hidden">
                <div
                  className="h-full bg-accent rounded-full transition-all duration-500"
                  style={{ width: `${Math.min(100, getVaultUtilization())}%` }}
                />
              </div>
            </div>

            <div className="bg-surface-1 rounded-lg border border-border p-6">
              <h3 className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">Share Price</h3>
              <p className="text-2xl font-bold font-mono text-gray-100">
                ${calculateShareValue()}
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
          {isLoadingUserData ? (
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
                  {userShares ? formatWad(userShares) : '0'} lvUSDT
                </p>
              </div>
              <div>
                <p className="text-xs text-gray-500 uppercase tracking-wide">Value</p>
                <p className="text-xl font-bold font-mono text-gray-100">
                  ${calculateUserAssets()} USDT
                </p>
              </div>
              <div>
                <p className="text-xs text-gray-500 uppercase tracking-wide">Est. Daily Yield</p>
                <p className="text-xl font-bold font-mono text-accent">
                  ${(parseFloat(calculateUserAssets()) * calculateAPY() / 100 / 365).toFixed(2)}
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
              <label className="block text-sm font-medium text-gray-400 mb-2">
                Amount (USDT)
              </label>
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
                Wallet Balance: {loadingUsdtBalance ? (
                  <Skeleton width="60px" height="16px" className="inline-block" />
                ) : (
                  <span className="font-mono text-gray-400">{usdtBalance ? formatUsdt(usdtBalance) : '0'} USDT</span>
                )}
              </p>
            </div>

            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-gray-500">You will receive:</span>
                <span className="font-medium font-mono text-gray-200">
                  {depositAmount ?
                    (parseFloat(depositAmount) / parseFloat(calculateShareValue())).toFixed(4) : '0'
                  } lvUSDT
                </span>
              </div>
            </div>

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
                disabled={!depositAmount}
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
              <label className="block text-sm font-medium text-gray-400 mb-2">
                Shares to Withdraw
              </label>
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
                Your Shares: {loadingUserShares ? (
                  <Skeleton width="60px" height="16px" className="inline-block" />
                ) : (
                  <span className="font-mono text-gray-400">{userShares ? formatWad(userShares) : '0'} lvUSDT</span>
                )}
              </p>
            </div>

            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-gray-500">You will receive:</span>
                <span className="font-medium font-mono text-gray-200">
                  {withdrawShares ?
                    (parseFloat(withdrawShares) * parseFloat(calculateShareValue())).toFixed(2) : '0'
                  } USDT
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-500">Withdrawal delay:</span>
                <span className="text-warning font-medium font-mono">48 hours</span>
              </div>
            </div>

            <button
              onClick={handleRequestWithdrawal}
              disabled={!withdrawShares || !userShares || userShares === BigInt(0)}
              className="w-full bg-warning text-surface-0 py-2.5 px-4 rounded-md font-semibold hover:bg-warning-dim disabled:opacity-30 transition-colors"
            >
              Request Withdrawal
            </button>

            <div className="bg-warning-muted border border-warning/20 rounded-lg p-3">
              <p className="text-sm text-gray-300">
                <span className="font-medium text-warning">Note:</span> Withdrawals require a 48-hour delay for security.
                You can cancel within 24 hours if needed.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Yield Breakdown */}
      <div className="bg-surface-1 rounded-lg border border-border p-6">
        <h3 className="text-lg font-semibold text-gray-100 mb-4">Yield Sources</h3>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="text-center">
            <div className="w-12 h-12 bg-accent-muted rounded-lg flex items-center justify-center mx-auto mb-3 border border-accent/20">
              <span className="text-accent font-bold font-mono">50%</span>
            </div>
            <h4 className="font-medium text-gray-200">Trading Fees</h4>
            <p className="text-sm text-gray-500 mt-1">
              0.10% on every trade execution
            </p>
          </div>

          <div className="text-center">
            <div className="w-12 h-12 bg-purple-muted rounded-lg flex items-center justify-center mx-auto mb-3 border border-purple/20">
              <span className="text-purple font-bold font-mono">30%</span>
            </div>
            <h4 className="font-medium text-gray-200">Borrow Fees</h4>
            <p className="text-sm text-gray-500 mt-1">
              Continuous fees from leveraged positions
            </p>
          </div>

          <div className="text-center">
            <div className="w-12 h-12 bg-warning-muted rounded-lg flex items-center justify-center mx-auto mb-3 border border-warning/20">
              <span className="text-warning font-bold font-mono">20%</span>
            </div>
            <h4 className="font-medium text-gray-200">Unmatched Funding</h4>
            <p className="text-sm text-gray-500 mt-1">
              Risk compensation from imbalanced positions
            </p>
          </div>
        </div>
      </div>

      {/* Get Test USDT */}
      <div className="bg-warning-muted border border-warning/20 rounded-lg p-4">
        <h4 className="font-medium text-warning mb-2">Need Test USDT?</h4>
        <p className="text-sm text-gray-400 mb-3">
          Get free test USDT for Base Sepolia testnet to try the vault
        </p>
        <button
          onClick={() => {
            approveUsdt({
              address: CONTRACT_ADDRESSES.usdt,
              abi: USDT_ABI,
              functionName: 'faucet',
              args: [],
            });
          }}
          className="bg-warning text-surface-0 py-2 px-4 rounded-md text-sm font-semibold hover:bg-warning-dim transition-colors"
        >
          Get 10,000 USDT
        </button>
      </div>
    </div>
  );
};

export default Vault;
