import React, { useState } from 'react';
import { useWriteContract, useReadContract, useWaitForTransactionReceipt } from 'wagmi';
import { useWallet } from '../hooks/useWallet';
import { parseUnits } from 'viem';
import { CONTRACT_ADDRESSES, formatUsdt, parseUsdt } from '../config/contracts';
import { EXECUTION_ENGINE_ABI, ACCOUNT_MANAGER_ABI, USDT_ABI } from '../config/abis';
import { useNotifications } from '../contexts/NotificationContext';
import Skeleton from './Skeleton';

interface TradeForm {
  marketId: string;
  direction: 'long' | 'short';
  collateral: string;
  leverage: string;
}

interface TradingProps {
  selectedTrade?: {
    marketId: string;
    marketName: string;
    direction: 'long' | 'short';
  } | null;
}

const Trading: React.FC<TradingProps> = ({ selectedTrade }) => {
  const { address } = useWallet();
  const { showSuccessToast, showErrorToast, showTradeConfirmation } = useNotifications();
  const [tradeForm, setTradeForm] = useState<TradeForm>({
    marketId: selectedTrade?.marketId || '',
    direction: selectedTrade?.direction || 'long',
    collateral: '',
    leverage: '1',
  });

  // Update form when selectedTrade changes
  React.useEffect(() => {
    if (selectedTrade) {
      setTradeForm(prev => ({
        ...prev,
        marketId: selectedTrade.marketId,
        direction: selectedTrade.direction,
      }));
    }
  }, [selectedTrade]);

  const { writeContract: openPosition, data: openTxHash, error: openError } = useWriteContract();
  const { writeContract: depositCollateral, data: depositTxHash, error: depositError } = useWriteContract();
  const { writeContract: approveUsdt, data: approveTxHash, error: approveError } = useWriteContract();

  // Watch for transaction confirmations
  const { isSuccess: openSuccess } = useWaitForTransactionReceipt({
    hash: openTxHash,
  });

  const { isSuccess: depositSuccess } = useWaitForTransactionReceipt({
    hash: depositTxHash,
  });

  const { isSuccess: approveSuccess } = useWaitForTransactionReceipt({
    hash: approveTxHash,
  });

  // Handle transaction success/error notifications
  React.useEffect(() => {
    if (openSuccess && openTxHash) {
      const marketName = selectedTrade?.marketName || 'Market Position';
      showTradeConfirmation('open', marketName, openTxHash);
    }
  }, [openSuccess, openTxHash, selectedTrade?.marketName, showTradeConfirmation]);

  React.useEffect(() => {
    if (openError) {
      showErrorToast(
        'Position Open Failed',
        'There was an error opening your position. Please try again.'
      );
    }
  }, [openError, showErrorToast]);

  React.useEffect(() => {
    if (depositSuccess && depositTxHash) {
      showSuccessToast(
        'Collateral Deposited',
        'Your collateral has been successfully deposited to your account.',
        depositTxHash
      );
    }
  }, [depositSuccess, depositTxHash, showSuccessToast]);

  React.useEffect(() => {
    if (depositError) {
      showErrorToast(
        'Deposit Failed',
        'There was an error depositing your collateral. Please try again.'
      );
    }
  }, [depositError, showErrorToast]);

  React.useEffect(() => {
    if (approveSuccess && approveTxHash) {
      showSuccessToast(
        'USDT Approved',
        'Your USDT spending has been approved.',
        approveTxHash
      );
    }
  }, [approveSuccess, approveTxHash, showSuccessToast]);

  React.useEffect(() => {
    if (approveError) {
      showErrorToast(
        'Approval Failed',
        'There was an error approving your USDT spending. Please try again.'
      );
    }
  }, [approveError, showErrorToast]);

  // Read user's USDT balance
  const { data: usdtBalance, isLoading: loadingUsdtBalance } = useReadContract({
    address: CONTRACT_ADDRESSES.usdt,
    abi: USDT_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
  });

  // Read user's account balance (deposited USDT)
  const { data: accountBalance, isLoading: loadingAccountBalance } = useReadContract({
    address: CONTRACT_ADDRESSES.accountManager,
    abi: ACCOUNT_MANAGER_ABI,
    functionName: 'getBalance',
    args: address ? [address] : undefined,
  });

  const handleInputChange = (field: keyof TradeForm, value: string) => {
    setTradeForm(prev => ({ ...prev, [field]: value }));
  };

  const handleApproveUsdt = async () => {
    if (!tradeForm.collateral) return;

    try {
      const amount = parseUsdt(tradeForm.collateral);
      await approveUsdt({
        address: CONTRACT_ADDRESSES.usdt,
        abi: USDT_ABI,
        functionName: 'approve',
        args: [CONTRACT_ADDRESSES.accountManager, amount],
      });
    } catch (error) {
      console.error('Error approving USDT:', error);
    }
  };

  const handleDeposit = async () => {
    if (!tradeForm.collateral) return;

    try {
      const amount = parseUsdt(tradeForm.collateral);
      await depositCollateral({
        address: CONTRACT_ADDRESSES.accountManager,
        abi: ACCOUNT_MANAGER_ABI,
        functionName: 'deposit',
        args: [amount],
      });
    } catch (error) {
      console.error('Error depositing collateral:', error);
    }
  };

  const handleOpenPosition = async () => {
    if (!tradeForm.marketId || !tradeForm.collateral || !tradeForm.leverage) return;

    try {
      const collateralAmount = parseUsdt(tradeForm.collateral);
      const leverage = parseUnits(tradeForm.leverage, 18);

      await openPosition({
        address: CONTRACT_ADDRESSES.executionEngine,
        abi: EXECUTION_ENGINE_ABI,
        functionName: 'openPosition',
        args: [{
          marketId: tradeForm.marketId as `0x${string}`,
          isLong: tradeForm.direction === 'long',
          collateral: collateralAmount,
          leverage: leverage,
        }],
      });

      // Reset form
      setTradeForm({
        marketId: '',
        direction: 'long',
        collateral: '',
        leverage: '1',
      });
    } catch (error) {
      console.error('Error opening position:', error);
    }
  };

  const calculatePositionSize = () => {
    if (!tradeForm.collateral || !tradeForm.leverage) return '0';
    const collateral = parseFloat(tradeForm.collateral);
    const leverage = parseFloat(tradeForm.leverage);
    return (collateral * leverage).toFixed(2);
  };

  const mockMarkets = selectedTrade
    ? [{ id: selectedTrade.marketId, name: selectedTrade.marketName }]
    : [
      { id: 'demo-1', name: 'Largest IPO by Market Cap 2026: SpaceX?' },
      { id: 'demo-2', name: 'US-Iran Ceasefire by April 30, 2026?' },
      { id: 'demo-3', name: 'Nothing Ever Happens: 2026' },
      { id: 'demo-4', name: '2026 FIFA World Cup Winner: Spain?' },
    ];

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-gray-100">Open Position</h2>
        <p className="text-gray-500">
          Take leveraged positions on binary prediction markets
        </p>
        {selectedTrade && (
          <div className="mt-2 p-3 bg-accent-muted border border-accent/20 rounded-lg">
            <p className="text-sm text-accent">
              <strong>Market selected:</strong> {selectedTrade.marketName} &bull; Direction: {selectedTrade.direction.toUpperCase()}
            </p>
          </div>
        )}
        {!address && (
          <div className="mt-2 p-3 bg-purple-muted border border-purple/20 rounded-lg">
            <p className="text-sm text-gray-300">
              <span className="font-medium text-purple">Demo mode:</span> Configure your position parameters below.
              Connect wallet to execute trades.
            </p>
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Trading Form */}
        <div className="lg:col-span-2">
          <div className="bg-surface-1 rounded-lg border border-border p-6">
            <h3 className="text-lg font-semibold text-gray-100 mb-4">Position Details</h3>

            <div className="space-y-4">
              {/* Market Selection */}
              <div>
                <label className="block text-sm font-medium text-gray-400 mb-2">
                  Select Market
                </label>
                <select
                  value={tradeForm.marketId}
                  onChange={(e) => handleInputChange('marketId', e.target.value)}
                  className="w-full rounded-md bg-surface-3 border-border text-gray-200 shadow-sm focus:border-accent focus:ring-accent/30"
                >
                  <option value="">Choose a market...</option>
                  {mockMarkets.map((market) => (
                    <option key={market.id} value={market.id}>
                      {market.name}
                    </option>
                  ))}
                </select>
              </div>

              {/* Direction */}
              <div>
                <label className="block text-sm font-medium text-gray-400 mb-2">
                  Direction
                </label>
                <div className="flex space-x-3">
                  <button
                    type="button"
                    onClick={() => handleInputChange('direction', 'long')}
                    className={`flex-1 py-2.5 px-4 rounded-md text-sm font-semibold transition-all ${
                      tradeForm.direction === 'long'
                        ? 'bg-accent/20 text-accent border border-accent/40 shadow-glow-green'
                        : 'bg-surface-3 text-gray-400 border border-border hover:border-border-light'
                    }`}
                  >
                    Long (Yes)
                  </button>
                  <button
                    type="button"
                    onClick={() => handleInputChange('direction', 'short')}
                    className={`flex-1 py-2.5 px-4 rounded-md text-sm font-semibold transition-all ${
                      tradeForm.direction === 'short'
                        ? 'bg-danger/20 text-danger border border-danger/40'
                        : 'bg-surface-3 text-gray-400 border border-border hover:border-border-light'
                    }`}
                  >
                    Short (No)
                  </button>
                </div>
              </div>

              {/* Collateral Amount */}
              <div>
                <label className="block text-sm font-medium text-gray-400 mb-2">
                  Collateral Amount (USDT)
                </label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={tradeForm.collateral}
                  onChange={(e) => handleInputChange('collateral', e.target.value)}
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

              {/* Leverage */}
              <div>
                <label className="block text-sm font-medium text-gray-400 mb-2">
                  Leverage: <span className="text-accent font-mono">{tradeForm.leverage}x</span>
                </label>
                <input
                  type="range"
                  min="1"
                  max="30"
                  step="0.5"
                  value={tradeForm.leverage}
                  onChange={(e) => handleInputChange('leverage', e.target.value)}
                  className="w-full"
                />
                <div className="flex justify-between text-xs text-gray-600 mt-1 font-mono">
                  <span>1x</span>
                  <span>15x</span>
                  <span>30x</span>
                </div>
              </div>
            </div>

            <div className="mt-6 pt-4 border-t border-border">
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-500">Position Size:</span>
                  <span className="font-medium font-mono text-gray-200">{calculatePositionSize()} USDT</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">Liquidation Risk:</span>
                  <span className={`font-medium ${
                    parseFloat(tradeForm.leverage) > 10 ? 'text-danger' : 'text-accent'
                  }`}>
                    {parseFloat(tradeForm.leverage) > 10 ? 'High' : 'Low'}
                  </span>
                </div>
              </div>
            </div>

            <div className="mt-6 space-y-3">
              {!address ? (
                <div className="text-center py-4 bg-surface-0 rounded-lg border border-border">
                  <p className="text-sm text-gray-400 mb-3">Connect wallet to execute this trade</p>
                  <p className="text-xs text-gray-600 font-mono">
                    Position value: {calculatePositionSize()} USDT &bull; Leverage: {tradeForm.leverage}x
                  </p>
                </div>
              ) : !accountBalance || accountBalance < parseUsdt(tradeForm.collateral || '0') ? (
                <div className="space-y-2">
                  <button
                    onClick={handleApproveUsdt}
                    disabled={!tradeForm.collateral}
                    className="w-full bg-accent text-surface-0 py-3 px-4 rounded-md font-semibold hover:bg-accent-dim disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                  >
                    1. Approve USDT
                  </button>
                  <button
                    onClick={handleDeposit}
                    disabled={!tradeForm.collateral}
                    className="w-full bg-purple text-white py-3 px-4 rounded-md font-semibold hover:bg-purple-dim disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                  >
                    2. Deposit Collateral
                  </button>
                </div>
              ) : (
                <button
                  onClick={handleOpenPosition}
                  disabled={!tradeForm.marketId || !tradeForm.collateral}
                  className="w-full bg-accent text-surface-0 py-3 px-4 rounded-md font-semibold hover:bg-accent-dim disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                >
                  Open Position
                </button>
              )}
            </div>
          </div>
        </div>

        {/* Account Info */}
        <div className="space-y-6">
          <div className="bg-surface-1 rounded-lg border border-border p-6">
            <h3 className="text-lg font-semibold text-gray-100 mb-4">Account</h3>
            <div className="space-y-3">
              <div className="flex justify-between">
                <span className="text-gray-500">USDT Balance:</span>
                <span className="font-medium font-mono text-gray-200">
                  {loadingUsdtBalance ? (
                    <Skeleton width="60px" height="20px" />
                  ) : (
                    `${usdtBalance ? formatUsdt(usdtBalance) : '0'} USDT`
                  )}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-500">Available Collateral:</span>
                <span className="font-medium font-mono text-gray-200">
                  {loadingAccountBalance ? (
                    <Skeleton width="60px" height="20px" />
                  ) : (
                    `${accountBalance ? formatUsdt(accountBalance) : '0'} USDT`
                  )}
                </span>
              </div>
            </div>
          </div>

          {/* Get Test USDT */}
          <div className="bg-warning-muted border border-warning/20 rounded-lg p-4">
            <h4 className="font-medium text-warning mb-2">Need Test USDT?</h4>
            <p className="text-sm text-gray-400 mb-3">
              Get free test USDT for Base Sepolia testnet
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
              className="w-full bg-warning text-surface-0 py-2 px-3 rounded-md text-sm font-semibold hover:bg-warning-dim transition-colors"
            >
              Get 10,000 USDT
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Trading;
