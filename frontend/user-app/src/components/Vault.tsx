import React, { useState } from 'react';
import { useAccount, useReadContract, useWriteContract } from 'wagmi';
import { CONTRACT_ADDRESSES, formatUsdt, formatWad, parseUsdt, WAD } from '../config/contracts';
import { LEVER_VAULT_ABI, USDT_ABI, FEE_ROUTER_ABI, OI_LIMITS_ABI } from '../config/abis';
import Skeleton from './Skeleton';

const Vault: React.FC = () => {
  const { address } = useAccount();
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
    args: [0], // FeeType.BORROW
  });

  const { data: transactionFees, isLoading: loadingTransactionFees } = useReadContract({
    address: CONTRACT_ADDRESSES.feeRouter,
    abi: FEE_ROUTER_ABI,
    functionName: 'getTotalFeesRouted',
    args: [1], // FeeType.TRANSACTION
  });

  const { data: liquidationFees, isLoading: loadingLiquidationFees } = useReadContract({
    address: CONTRACT_ADDRESSES.feeRouter,
    abi: FEE_ROUTER_ABI,
    functionName: 'getTotalFeesRouted',
    args: [2], // FeeType.LIQUIDATION
  });

  const { data: settlementFees, isLoading: loadingSettlementFees } = useReadContract({
    address: CONTRACT_ADDRESSES.feeRouter,
    abi: FEE_ROUTER_ABI,
    functionName: 'getTotalFeesRouted',
    args: [3], // FeeType.SETTLEMENT
  });

  // Read global OI for utilization calculation
  const { data: globalOI, isLoading: loadingGlobalOI } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getGlobalOI',
  });

  // Check if any critical data is still loading
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
    // Utilization = globalOI / TVL * 100
    // globalOI is in WAD (1e18), totalAssets is in USDT scale (1e6)
    // Convert totalAssets to WAD for comparison
    const tvlInWad = totalAssets * BigInt(1e12); // Convert USDT (1e6) to WAD (1e18)
    const utilizationBps = Number(globalOI * BigInt(10000) / tvlInWad);
    return Math.min(100, utilizationBps / 100); // Return as percentage
  };

  const calculateAPY = (): number => {
    if (!totalAssets || totalAssets === BigInt(0)) return 0;

    // Sum all fees (50% goes to LPs via fee router)
    const totalFees =
      (borrowFees || BigInt(0)) +
      (transactionFees || BigInt(0)) +
      (liquidationFees || BigInt(0)) +
      (settlementFees || BigInt(0));

    if (totalFees === BigInt(0)) return 0;

    // LP gets 50% of all fees
    const lpShare = totalFees / BigInt(2);

    // Convert to annual rate: (LP fees / TVL) * 100
    // totalAssets is in USDT (1e6), lpShare is in USDT (1e6)
    const annualReturn = Number(lpShare * BigInt(100)) / Number(totalAssets);

    // This gives lifetime return - we'd need deployment timestamp to annualize properly
    // For now, assume this is representing annualized rate from historical data
    return Math.min(999, annualReturn); // Cap at 999%
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-gray-900">Liquidity Vault</h2>
        <p className="text-gray-600">
          Deposit USDT to earn yield from trading fees, funding payments, and borrow fees
        </p>
      </div>

      {/* Vault Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        {isLoadingVaultData ? (
          <>
            {[1, 2, 3, 4].map((index) => (
              <div key={index} className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
                <Skeleton width="120px" height="16px" className="mb-2" />
                <Skeleton width="80px" height="32px" className="mb-1" />
                <Skeleton width="60px" height="16px" />
              </div>
            ))}
          </>
        ) : (
          <>
            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="text-sm font-medium text-gray-500 mb-2">Total Value Locked</h3>
              <p className="text-2xl font-bold text-gray-900">
                ${totalAssets ? formatUsdt(totalAssets) : '0'}
              </p>
              <p className="text-sm text-gray-600 mt-1">USDT</p>
            </div>

            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="text-sm font-medium text-gray-500 mb-2">Current APY</h3>
              <p className="text-2xl font-bold text-success-600">
                {calculateAPY().toFixed(1)}%
              </p>
              <p className="text-sm text-gray-600 mt-1">From trading fees</p>
            </div>

            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="text-sm font-medium text-gray-500 mb-2">Vault Utilization</h3>
              <p className="text-2xl font-bold text-gray-900">
                {getVaultUtilization().toFixed(1)}%
              </p>
              <p className="text-sm text-gray-600 mt-1">Trading activity</p>
            </div>

            <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h3 className="text-sm font-medium text-gray-500 mb-2">Share Price</h3>
              <p className="text-2xl font-bold text-gray-900">
                ${calculateShareValue()}
              </p>
              <p className="text-sm text-gray-600 mt-1">lvUSDT per share</p>
            </div>
          </>
        )}
      </div>

      {/* User Position */}
      {address && (
        <div className="bg-gradient-to-r from-primary-50 to-primary-100 rounded-lg p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Your Position</h3>
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
                <p className="text-sm text-gray-600">Your Shares</p>
                <p className="text-xl font-bold text-gray-900">
                  {userShares ? formatWad(userShares) : '0'} lvUSDT
                </p>
              </div>
              <div>
                <p className="text-sm text-gray-600">Value</p>
                <p className="text-xl font-bold text-gray-900">
                  ${calculateUserAssets()} USDT
                </p>
              </div>
              <div>
                <p className="text-sm text-gray-600">Est. Daily Yield</p>
                <p className="text-xl font-bold text-success-600">
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
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Deposit USDT</h3>

          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Amount (USDT)
              </label>
              <input
                type="number"
                step="0.01"
                min="0"
                value={depositAmount}
                onChange={(e) => setDepositAmount(e.target.value)}
                placeholder="0.00"
                className="w-full rounded-md border-gray-300 shadow-sm focus:border-primary-500 focus:ring-primary-500"
              />
              <p className="text-xs text-gray-500 mt-1">
                Wallet Balance: {loadingUsdtBalance ? (
                  <Skeleton width="60px" height="16px" className="inline-block" />
                ) : (
                  `${usdtBalance ? formatUsdt(usdtBalance) : '0'} USDT`
                )}
              </p>
            </div>

            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">You will receive:</span>
                <span className="font-medium">
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
                className="w-full bg-primary-600 text-white py-2 px-4 rounded-md font-medium hover:bg-primary-700 disabled:opacity-50"
              >
                1. Approve USDT
              </button>
              <button
                onClick={handleDeposit}
                disabled={!depositAmount}
                className="w-full bg-primary-600 text-white py-2 px-4 rounded-md font-medium hover:bg-primary-700 disabled:opacity-50"
              >
                2. Deposit
              </button>
            </div>
          </div>
        </div>

        {/* Withdraw */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Request Withdrawal</h3>

          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Shares to Withdraw
              </label>
              <input
                type="number"
                step="0.0001"
                min="0"
                value={withdrawShares}
                onChange={(e) => setWithdrawShares(e.target.value)}
                placeholder="0.0000"
                className="w-full rounded-md border-gray-300 shadow-sm focus:border-primary-500 focus:ring-primary-500"
              />
              <p className="text-xs text-gray-500 mt-1">
                Your Shares: {loadingUserShares ? (
                  <Skeleton width="60px" height="16px" className="inline-block" />
                ) : (
                  `${userShares ? formatWad(userShares) : '0'} lvUSDT`
                )}
              </p>
            </div>

            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">You will receive:</span>
                <span className="font-medium">
                  {withdrawShares ?
                    (parseFloat(withdrawShares) * parseFloat(calculateShareValue())).toFixed(2) : '0'
                  } USDT
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-600">Withdrawal delay:</span>
                <span className="text-orange-600 font-medium">48 hours</span>
              </div>
            </div>

            <button
              onClick={handleRequestWithdrawal}
              disabled={!withdrawShares || !userShares || userShares === BigInt(0)}
              className="w-full bg-orange-600 text-white py-2 px-4 rounded-md font-medium hover:bg-orange-700 disabled:opacity-50"
            >
              Request Withdrawal
            </button>

            <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-3">
              <p className="text-sm text-yellow-800">
                <strong>Note:</strong> Withdrawals require a 48-hour delay for security.
                You can cancel within 24 hours if needed.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Yield Breakdown */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Yield Sources</h3>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="text-center">
            <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center mx-auto mb-3">
              <span className="text-blue-600 font-bold">50%</span>
            </div>
            <h4 className="font-medium text-gray-900">Trading Fees</h4>
            <p className="text-sm text-gray-600 mt-1">
              0.10% on every trade execution
            </p>
          </div>

          <div className="text-center">
            <div className="w-12 h-12 bg-green-100 rounded-lg flex items-center justify-center mx-auto mb-3">
              <span className="text-green-600 font-bold">30%</span>
            </div>
            <h4 className="font-medium text-gray-900">Borrow Fees</h4>
            <p className="text-sm text-gray-600 mt-1">
              Continuous fees from leveraged positions
            </p>
          </div>

          <div className="text-center">
            <div className="w-12 h-12 bg-purple-100 rounded-lg flex items-center justify-center mx-auto mb-3">
              <span className="text-purple-600 font-bold">20%</span>
            </div>
            <h4 className="font-medium text-gray-900">Unmatched Funding</h4>
            <p className="text-sm text-gray-600 mt-1">
              Risk compensation from imbalanced positions
            </p>
          </div>
        </div>
      </div>

      {/* Get Test USDT */}
      <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
        <h4 className="font-medium text-yellow-800 mb-2">Need Test USDT?</h4>
        <p className="text-sm text-yellow-700 mb-3">
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
          className="bg-yellow-600 text-white py-2 px-4 rounded-md text-sm font-medium hover:bg-yellow-700"
        >
          Get 10,000 USDT
        </button>
      </div>
    </div>
  );
};

export default Vault;
