import React, { useState } from 'react';
import { useWriteContract, useReadContract, useWaitForTransactionReceipt } from 'wagmi';
import { useWallet } from '../hooks/useWallet';
import { parseUnits, createWalletClient, createPublicClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { baseSepolia } from 'wagmi/chains';
import { CONTRACT_ADDRESSES, formatUsdt, parseUsdt, loadContractAddresses, clearAddressCache } from '../config/contracts';
import { EXECUTION_ENGINE_ABI, ACCOUNT_MANAGER_ABI, USDT_ABI, LEVERAGE_MODEL_ABI, OI_LIMITS_ABI } from '../config/abis';
import { useNotifications } from '../contexts/NotificationContext';
import { useMarketProbabilities } from '../hooks/useMarketProbabilities';
import { useDemo } from '../contexts/DemoContext';
import Skeleton from './Skeleton';
import TestnetDisclaimer from './TestnetDisclaimer';
import LiveDataIndicator from './LiveDataIndicator';
import SecurityBadges from './SecurityBadges';

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
  const { address, isDemoMode } = useWallet();
  const { showSuccessToast, showErrorToast, showTradeConfirmation } = useNotifications();
  const { markets: onChainMarkets } = useMarketProbabilities();
  const { testWalletKey } = useDemo();
  const [isAutoFunding, setIsAutoFunding] = useState(false);
  const [tradeForm, setTradeForm] = useState<TradeForm>({
    marketId: selectedTrade?.marketId || '',
    direction: selectedTrade?.direction || 'long',
    collateral: '',
    leverage: '5',
  });

  // Load contract addresses on component mount
  React.useEffect(() => {
    const initializeAddresses = async () => {
      try {
        // Clear cache to ensure we load fresh addresses
        clearAddressCache();
        await loadContractAddresses();
        console.log('Contract addresses reloaded successfully');
      } catch (error) {
        console.error('Error reloading contract addresses:', error);
      }
    };

    initializeAddresses();
  }, []);

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

  // Demo mode transaction handler
  const sendDemoTransaction = async (contractAddress: `0x${string}`, abi: any, functionName: string, args: any[]) => {
    if (!isDemoMode) return;

    try {
      const account = privateKeyToAccount(`0x${testWalletKey}` as `0x${string}`);

      const publicClient = createPublicClient({
        chain: baseSepolia,
        transport: http('https://base-sepolia-rpc.publicnode.com'),
      });

      const walletClient = createWalletClient({
        account,
        chain: baseSepolia,
        transport: http('https://base-sepolia-rpc.publicnode.com'),
      });

      // Write directly - signs locally, sends via eth_sendRawTransaction
      const hash = await walletClient.writeContract({
        address: contractAddress,
        abi,
        functionName,
        args,
        account,
        chain: baseSepolia,
        gas: 2000000n,
      });
      console.log('Demo transaction sent:', hash);
      return hash;
    } catch (error: any) {
      console.error('Demo transaction failed:', error?.shortMessage || error?.message);
      throw error;
    }
  };

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
      let errorMessage = 'There was an error opening your position. Please try again.';

      // Try to extract meaningful error from multiple possible locations
      const fullErrorText = [
        openError.message,
        (openError as any).shortMessage,
        (openError as any).details,
        (openError as any).reason,
        (openError as any).data?.message,
        (openError as any).cause?.reason,
      ].filter(Boolean).join(' | ');

      // Check for specific error patterns
      if (fullErrorText.includes('LeverageExceedsMax') || fullErrorText.includes('ExceedsMaxLeverage')) {
        errorMessage = `The requested leverage (${tradeForm.leverage}x) exceeds the maximum allowed (${maxLeverage.toFixed(1)}x) for this market. Please reduce leverage.`;
      } else if (fullErrorText.includes('InsufficientCollateral') || fullErrorText.includes('InsufficientBalance')) {
        errorMessage = 'Insufficient collateral. Please deposit more USDT to your account or reduce position size.';
      } else if (fullErrorText.includes('MarketNotActive') || fullErrorText.includes('MarketNotLive')) {
        errorMessage = 'This market is not currently active for trading. Please select a different market.';
      } else if (fullErrorText.includes('ZeroDepthThreshold') || fullErrorText.includes('InsufficientDepth')) {
        errorMessage = 'Market depth is too low for this trade size. Try a smaller position.';
      } else if (fullErrorText.includes('MarketNotFound') || fullErrorText.includes('InvalidMarket')) {
        errorMessage = 'Market not found. Please select a valid market.';
      } else if (fullErrorText.includes('AccessControlUnauthorized') || fullErrorText.includes('Unauthorized')) {
        errorMessage = 'Access denied. Please try reconnecting your wallet.';
      } else if (fullErrorText.includes('OICapExceeded') || fullErrorText.includes('ExceedsOICap')) {
        errorMessage = 'This position would exceed the open interest cap for this market. Try a smaller position.';
      } else if (fullErrorText.includes('PriceTooStale') || fullErrorText.includes('StalePrice')) {
        errorMessage = 'Price data is too stale. Please wait a moment and try again.';
      } else if (fullErrorText.includes('execution reverted')) {
        // Extract custom error from execution reverted message
        const match = fullErrorText.match(/execution reverted: ([^,)]+)/);
        if (match) {
          errorMessage = `Transaction failed: ${match[1]}. Please check your parameters and try again.`;
        }
      }

      showErrorToast(
        'Position Open Failed',
        errorMessage
      );
    }
  }, [openError, showErrorToast, tradeForm.leverage]);

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

  // Read maximum leverage for selected market
  const { data: maxLeverageRaw, isLoading: loadingMaxLeverage } = useReadContract({
    address: CONTRACT_ADDRESSES.leverageModel,
    abi: LEVERAGE_MODEL_ABI,
    functionName: 'getEffectiveMaxLeverage',
    args: tradeForm.marketId ? [tradeForm.marketId as `0x${string}`] : undefined,
  });

  const maxLeverage = maxLeverageRaw ? Number(maxLeverageRaw) / 1e18 : 30; // Convert from WAD to decimal, default to 30

  // Read OI caps and current OI for max position calculation
  const marketIdHex = tradeForm.marketId ? tradeForm.marketId as `0x${string}` : undefined;
  const isLong = tradeForm.direction === 'long';

  // OI caps from NEW OILimits (reads correct TVL)
  const { data: globalOICapRaw } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimitsNew,
    abi: OI_LIMITS_ABI,
    functionName: 'getGlobalOICap',
    query: { enabled: !!marketIdHex },
  });

  const { data: marketOICapRaw } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimitsNew,
    abi: OI_LIMITS_ABI,
    functionName: 'getMarketOICap',
    args: marketIdHex ? [marketIdHex] : undefined,
    query: { enabled: !!marketIdHex },
  });

  const { data: sideOICapRaw } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimitsNew,
    abi: OI_LIMITS_ABI,
    functionName: 'getSideOICap',
    args: marketIdHex ? [marketIdHex] : undefined,
    query: { enabled: !!marketIdHex },
  });

  const { data: userOICapRaw } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimitsNew,
    abi: OI_LIMITS_ABI,
    functionName: 'getUserOICap',
    args: marketIdHex ? [marketIdHex] : undefined,
    query: { enabled: !!marketIdHex },
  });

  // Current OI from OLD OILimits (where ExecutionEngine writes)
  const { data: globalOIRaw } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getGlobalOI',
    query: { enabled: !!marketIdHex },
  });

  const { data: marketOIRaw } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getMarketOI',
    args: marketIdHex ? [marketIdHex] : undefined,
    query: { enabled: !!marketIdHex },
  });

  const { data: sideOIRaw } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getSideOI',
    args: marketIdHex ? [marketIdHex, isLong] : undefined,
    query: { enabled: !!marketIdHex },
  });

  const { data: userOIRaw } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getUserOI',
    args: marketIdHex && address ? [marketIdHex, address] : undefined,
    query: { enabled: !!marketIdHex && !!address },
  });

  // Compute max position size from all 4 OI cap tiers + balance
  const maxPositionInfo = React.useMemo(() => {
    if (!marketIdHex) return null;

    const lev = parseFloat(tradeForm.leverage) || 1;
    const amBal = accountBalance ? Number(accountBalance) : 0;

    // All 4 tiers: cap - current = remaining
    const tiers: { name: string; cap: number; current: number; remaining: number }[] = [
      {
        name: 'Global OI',
        cap: globalOICapRaw ? Number(globalOICapRaw) : 0,
        current: globalOIRaw ? Number(globalOIRaw) : 0,
        remaining: 0,
      },
      {
        name: 'Market OI',
        cap: marketOICapRaw ? Number(marketOICapRaw) : 0,
        current: marketOIRaw ? Number(marketOIRaw) : 0,
        remaining: 0,
      },
      {
        name: 'Side OI',
        cap: sideOICapRaw ? Number(sideOICapRaw) : 0,
        current: sideOIRaw ? Number(sideOIRaw) : 0,
        remaining: 0,
      },
      {
        name: 'Per-user OI',
        cap: userOICapRaw ? Number(userOICapRaw) : 0,
        current: userOIRaw ? Number(userOIRaw) : 0,
        remaining: 0,
      },
    ];
    tiers.forEach(t => { t.remaining = Math.max(0, t.cap - t.current); });

    const balanceTier = { name: 'Account balance', cap: amBal, remaining: amBal * lev };

    // Find the tightest OI constraint
    const tightestOI = tiers.reduce((min, t) => t.remaining < min.remaining ? t : min, tiers[0]);
    const oiLimit = tightestOI.remaining;

    // Compare OI limit vs balance-derived notional
    const maxNotionalFromBalance = balanceTier.remaining;
    const isBoundByBalance = maxNotionalFromBalance < oiLimit;
    const maxNotional = Math.min(oiLimit, maxNotionalFromBalance);
    const maxCollateral = lev > 0 ? maxNotional / lev : 0;

    const binding = isBoundByBalance ? balanceTier : tightestOI;

    return {
      maxNotional: maxNotional / 1e6,
      maxCollateral: maxCollateral / 1e6,
      bindingName: binding.name,
      bindingCap: (isBoundByBalance ? binding.cap : binding.cap) / 1e6,
      bindingRemaining: binding.remaining / 1e6,
      tiers: tiers.map(t => ({ ...t, cap: t.cap / 1e6, current: t.current / 1e6, remaining: t.remaining / 1e6 })),
      balanceUsd: amBal / 1e6,
    };
  }, [marketIdHex, globalOICapRaw, globalOIRaw, marketOICapRaw, marketOIRaw,
      sideOICapRaw, sideOIRaw, userOICapRaw, userOIRaw, accountBalance, tradeForm.leverage]);

  const handleInputChange = (field: keyof TradeForm, value: string) => {
    // Cap leverage to maximum allowed
    if (field === 'leverage') {
      const leverageValue = parseFloat(value);
      if (leverageValue > maxLeverage) {
        value = maxLeverage.toFixed(1);
      }
    }
    setTradeForm(prev => ({ ...prev, [field]: value }));
  };

  const handleApproveUsdt = async () => {
    if (!tradeForm.collateral) return;

    try {
      const amount = parseUsdt(tradeForm.collateral);
      if (isDemoMode) {
        const hash = await sendDemoTransaction(
          CONTRACT_ADDRESSES.usdt,
          USDT_ABI,
          'approve',
          [CONTRACT_ADDRESSES.accountManager, amount]
        );
        if (hash) {
          showSuccessToast('USDT Approved', 'Your USDT spending has been approved.', hash);
        }
      } else {
        await approveUsdt({
          address: CONTRACT_ADDRESSES.usdt,
          abi: USDT_ABI,
          functionName: 'approve',
          args: [CONTRACT_ADDRESSES.accountManager, amount],
        });
      }
    } catch (error: any) {
      console.error('Error approving USDT:', error);
      showErrorToast('Approval Failed', 'There was an error approving your USDT spending. Please try again.');
    }
  };

  const handleDeposit = async () => {
    if (!tradeForm.collateral) return;

    try {
      const amount = parseUsdt(tradeForm.collateral);
      if (isDemoMode) {
        const hash = await sendDemoTransaction(
          CONTRACT_ADDRESSES.accountManager,
          ACCOUNT_MANAGER_ABI,
          'deposit',
          [amount]
        );
        if (hash) {
          showSuccessToast('Collateral Deposited', 'Your collateral has been successfully deposited to your account.', hash);
        }
      } else {
        await depositCollateral({
          address: CONTRACT_ADDRESSES.accountManager,
          abi: ACCOUNT_MANAGER_ABI,
          functionName: 'deposit',
          args: [amount],
        });
      }
    } catch (error: any) {
      console.error('Error depositing collateral:', error);
      showErrorToast('Deposit Failed', 'There was an error depositing your collateral. Please try again.');
    }
  };

  const handleOpenPosition = async () => {
    if (!tradeForm.marketId || !tradeForm.collateral || !tradeForm.leverage) return;

    try {
      const collateralAmount = parseUsdt(tradeForm.collateral);
      const leverage = parseUnits(tradeForm.leverage, 18);

      // Debug logging
      console.log('Opening position with params:', {
        marketId: tradeForm.marketId,
        isLong: tradeForm.direction === 'long',
        collateral: collateralAmount.toString(),
        leverage: leverage.toString(),
        leverageDecimal: tradeForm.leverage,
        maxLeverage: maxLeverage.toFixed(1),
        executionEngineAddress: CONTRACT_ADDRESSES.executionEngine,
        leverageModelAddress: CONTRACT_ADDRESSES.leverageModel,
      });

      if (isDemoMode) {
        setIsAutoFunding(true);
        // Auto-approve USDT for AccountManager
        try {
          await sendDemoTransaction(
            CONTRACT_ADDRESSES.usdt,
            USDT_ABI,
            'approve',
            [CONTRACT_ADDRESSES.accountManager, BigInt('115792089237316195423570985008687907853269984665640564039457584007913129639935')]
          );
        } catch (e) { console.log('Approve already set:', e); }
        // Auto-deposit collateral
        try {
          await sendDemoTransaction(
            CONTRACT_ADDRESSES.accountManager,
            ACCOUNT_MANAGER_ABI,
            'deposit',
            [collateralAmount]
          );
        } catch (e) { console.log('Deposit skipped:', e); }
        setIsAutoFunding(false);
        // Open position
        const hash = await sendDemoTransaction(
          CONTRACT_ADDRESSES.executionEngine,
          EXECUTION_ENGINE_ABI,
          'openPosition',
          [{
            marketId: tradeForm.marketId as `0x${string}`,
            isLong: tradeForm.direction === 'long',
            collateral: collateralAmount,
            leverage: leverage,
          }]
        );

        if (hash) {
          const marketName = selectedTrade?.marketName || 'Market Position';
          showTradeConfirmation('open', marketName, hash);
        }
      } else {
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
      }

      // Reset form
      setTradeForm({
        marketId: '',
        direction: 'long',
        collateral: '',
        leverage: '5',
      });
    } catch (error: any) {
      console.error('Error opening position:', error);

      const reason = error?.shortMessage || error?.cause?.shortMessage || error?.message || 'Transaction failed';

      showErrorToast(
        'Position Open Failed',
        reason
      );
    }
  };

  const calculatePositionSize = () => {
    if (!tradeForm.collateral || !tradeForm.leverage) return '0';
    const collateral = parseFloat(tradeForm.collateral);
    const leverage = parseFloat(tradeForm.leverage);
    return (collateral * leverage).toFixed(2);
  };

  const availableMarkets = selectedTrade
    ? [{ id: selectedTrade.marketId, name: selectedTrade.marketName }]
    : onChainMarkets.map(m => ({ id: m.id, name: m.name }));

  return (
    <div className="space-y-6">
      <div>
        <h2 className="lever-heading-lg">Open Position</h2>
        <p className="lever-subtitle mt-1">
          Take leveraged positions on binary prediction markets
        </p>
        <div className="flex items-center space-x-4 mt-3">
          <SecurityBadges />
        </div>
      </div>

      {/* Testnet Notice */}
      <TestnetDisclaimer compact={true} context="trading" />

      <div>
        {selectedTrade && (
          <div className="mt-2 p-3 bg-accent-muted border border-accent/20 rounded-lg">
            <p className="text-sm text-accent">
              <strong>Market selected:</strong> {selectedTrade.marketName} &bull; Direction: {selectedTrade.direction.toUpperCase()}
            </p>
          </div>
        )}
        {isDemoMode && (
          <div className="mt-2 p-3 bg-purple-muted border border-purple/20 rounded-lg">
            <p className="text-sm text-gray-300">
              <span className="font-medium text-purple">Demo mode:</span> Configure your position parameters below.
              Transactions will be executed with the test wallet.
            </p>
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Trading Form */}
        <div className="lg:col-span-2">
          <div className="lever-trading-panel">
            <div className="flex items-center justify-between mb-6">
              <h3 className="lever-heading-md">Position Details</h3>
              <div className="flex items-center space-x-3">
                <LiveDataIndicator
                  label="ORACLE"
                  value="LIVE"
                  status="live"
                  compact={true}
                />
                <LiveDataIndicator
                  label="DEPTH"
                  value={maxLeverage ? `${maxLeverage.toFixed(1)}x` : "30x"}
                  status="live"
                  compact={true}
                />
              </div>
            </div>

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
                  {availableMarkets.map((market) => (
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
                  {loadingMaxLeverage ? (
                    <span className="ml-2 text-xs text-gray-500">Loading max...</span>
                  ) : (
                    <span className="ml-2 text-xs text-gray-500">
                      (max: {maxLeverage.toFixed(1)}x)
                    </span>
                  )}
                </label>
                <input
                  type="range"
                  min="1"
                  max={Math.min(maxLeverage, 30)}
                  step="0.1"
                  value={Math.min(parseFloat(tradeForm.leverage), maxLeverage)}
                  onChange={(e) => handleInputChange('leverage', e.target.value)}
                  className="w-full"
                />
                <div className="flex justify-between text-xs text-gray-600 mt-1 font-mono">
                  <span>1x</span>
                  <span>{Math.min(maxLeverage / 2, 15).toFixed(1)}x</span>
                  <span>{Math.min(maxLeverage, 30).toFixed(1)}x</span>
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
                {maxPositionInfo && (
                  <>
                    <div className="flex justify-between">
                      <span className="text-gray-500">Max Position:</span>
                      <span className="font-medium font-mono text-gray-200">
                        ${maxPositionInfo.maxNotional.toLocaleString('en-US', { maximumFractionDigits: 0 })} notional
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-500">Max Collateral:</span>
                      <span className="font-medium font-mono text-gray-200">
                        ${maxPositionInfo.maxCollateral.toLocaleString('en-US', { maximumFractionDigits: 0 })} USDT
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-gray-500">Binding Limit:</span>
                      <span className="font-medium text-xs text-gray-400">
                        {maxPositionInfo.bindingName} — ${maxPositionInfo.bindingRemaining.toLocaleString('en-US', { maximumFractionDigits: 0 })} remaining
                      </span>
                    </div>
                    <div className="pt-2 mt-2 border-t border-border/50 space-y-1">
                      <div className="text-[10px] uppercase tracking-wider text-gray-600 mb-1">OI Capacity</div>
                      {maxPositionInfo.tiers.map(t => (
                        <div key={t.name} className="flex justify-between text-xs">
                          <span className="text-gray-600">{t.name}:</span>
                          <span className="font-mono text-gray-500">
                            ${t.current.toLocaleString('en-US', { maximumFractionDigits: 0 })} / ${t.cap.toLocaleString('en-US', { maximumFractionDigits: 0 })}
                          </span>
                        </div>
                      ))}
                      <div className="flex justify-between text-xs">
                        <span className="text-gray-600">Balance:</span>
                        <span className="font-mono text-gray-500">
                          ${maxPositionInfo.balanceUsd.toLocaleString('en-US', { maximumFractionDigits: 0 })} × {tradeForm.leverage}x
                        </span>
                      </div>
                    </div>
                  </>
                )}
              </div>
            </div>

            <div className="mt-6 space-y-3">
              {!address && !isDemoMode ? (
                <div className="text-center py-4 bg-surface-0 rounded-lg border border-border">
                  <p className="text-sm text-gray-400 mb-3">Connect wallet to execute this trade</p>
                  <p className="text-xs text-gray-600 font-mono">
                    Position value: {calculatePositionSize()} USDT &bull; Leverage: {tradeForm.leverage}x
                  </p>
                </div>
              ) : isDemoMode ? (
                <button
                  onClick={handleOpenPosition}
                  disabled={!tradeForm.marketId || !tradeForm.collateral || isAutoFunding}
                  className="w-full bg-accent text-surface-0 py-3 px-4 rounded-md font-semibold hover:bg-accent-dim disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                >
                  {isAutoFunding ? 'Setting up account...' : 'Open Position'}
                </button>
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
          {/* Live Account Metrics */}
          <div className="space-y-3">
            <h3 className="lever-heading-sm mb-4">Live Account Metrics</h3>
            <LiveDataIndicator
              label="USDT Balance"
              value={loadingUsdtBalance ? "Loading..." : `${usdtBalance ? formatUsdt(usdtBalance) : '0'} USDT`}
              status={loadingUsdtBalance ? "loading" : "live"}
              sublabel="Wallet Balance"
            />
            <LiveDataIndicator
              label="Available Collateral"
              value={loadingAccountBalance ? "Loading..." : `${accountBalance ? formatUsdt(accountBalance) : '0'} USDT`}
              status={loadingAccountBalance ? "loading" : "live"}
              sublabel="Ready for Trading"
            />
          </div>

          <div className="lever-metric-card">
            <h3 className="lever-heading-sm mb-4">Account Details</h3>
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
              onClick={async () => {
                if (isDemoMode) {
                  try {
                    const hash = await sendDemoTransaction(
                      CONTRACT_ADDRESSES.usdt,
                      USDT_ABI,
                      'faucet',
                      []
                    );
                    if (hash) {
                      showSuccessToast('USDT Faucet', 'You received 10,000 test USDT.', hash);
                    }
                  } catch (error: any) {
                    console.error('Faucet error:', error);
                    showErrorToast('Faucet Failed', 'There was an error getting test USDT.');
                  }
                } else {
                  approveUsdt({
                    address: CONTRACT_ADDRESSES.usdt,
                    abi: USDT_ABI,
                    functionName: 'faucet',
                    args: [],
                  });
                }
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
