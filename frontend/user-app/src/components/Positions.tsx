import React, { useState, useEffect, useCallback } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { CONTRACT_ADDRESSES, formatWad, WAD } from '../config/contracts';
import {
  POSITION_MANAGER_ABI,
  EXECUTION_ENGINE_ABI,
  ORACLE_ADAPTER_ABI,
  MARKET_REGISTRY_ABI,
  ACCOUNT_MANAGER_ABI,
  BORROW_FEE_ENGINE_ABI,
  FUNDING_RATE_ENGINE_ABI,
} from '../config/abis';
import { useLivePrices } from '../hooks/useLivePrices';
import TradeHistory from './TradeHistory';
import Skeleton from './Skeleton';

interface PositionData {
  id: bigint;
  marketId: `0x${string}`;
  marketName: string;
  isLong: boolean;
  collateral: bigint;
  positionSize: bigint;
  entryPI: bigint;
  entryPrice: bigint;
  leverage: bigint;
  currentPI: bigint;
  pnl: bigint;
  borrowFees: bigint;
  fundingAccrued: bigint;
  equity: bigint;
  isOpen: boolean;
}

type CloseState = 'idle' | 'confirming' | 'pending' | 'success' | 'error';

const Positions: React.FC = () => {
  const { address } = useAccount();
  const [positions, setPositions] = useState<PositionData[]>([]);
  const [selectedPositionId, setSelectedPositionId] = useState<bigint | null>(null);
  const [closeState, setCloseState] = useState<CloseState>('idle');
  const [closeError, setCloseError] = useState<string>('');
  const [closedPositionPnl, setClosedPositionPnl] = useState<bigint | null>(null);

  const { writeContract, data: txHash, error: writeError, reset: resetWrite } = useWriteContract();

  const { isSuccess: txConfirmed, isLoading: txPending } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const { data: positionIds, refetch: refetchPositionIds, isLoading: loadingPositionIds } = useReadContract({
    address: CONTRACT_ADDRESSES.positionManager,
    abi: POSITION_MANAGER_ABI,
    functionName: 'getUserPositions',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: accountBalance, refetch: refetchBalance, isLoading: loadingAccountBalance } = useReadContract({
    address: CONTRACT_ADDRESSES.accountManager,
    abi: ACCOUNT_MANAGER_ABI,
    functionName: 'getBalance',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: freeCollateral, refetch: refetchFreeCollateral, isLoading: loadingFreeCollateral } = useReadContract({
    address: CONTRACT_ADDRESSES.accountManager,
    abi: ACCOUNT_MANAGER_ABI,
    functionName: 'getFreeCollateral',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const isLoadingAccountData = address && (loadingAccountBalance || loadingFreeCollateral);
  const isLoadingPositions = address && loadingPositionIds;

  useEffect(() => {
    if (txPending && closeState === 'confirming') {
      setCloseState('pending');
    }
  }, [txPending, closeState]);

  useEffect(() => {
    if (txConfirmed && (closeState === 'pending' || closeState === 'confirming')) {
      setCloseState('success');
      refetchPositionIds();
      refetchBalance();
      refetchFreeCollateral();
      const timer = setTimeout(() => {
        setCloseState('idle');
        setSelectedPositionId(null);
        setClosedPositionPnl(null);
      }, 5000);
      return () => clearTimeout(timer);
    }
  }, [txConfirmed, closeState, refetchPositionIds, refetchBalance, refetchFreeCollateral]);

  useEffect(() => {
    if (writeError) {
      setCloseState('error');
      setCloseError(writeError.message?.slice(0, 200) || 'Transaction failed');
    }
  }, [writeError]);

  const fetchPositionDetails = useCallback(async () => {
    if (!positionIds || !Array.isArray(positionIds) || positionIds.length === 0) {
      setPositions([]);
      return;
    }

    const posData: PositionData[] = (positionIds as bigint[]).map((id) => ({
      id,
      marketId: '0x0000000000000000000000000000000000000000000000000000000000000000' as `0x${string}`,
      marketName: `Position #${id.toString()}`,
      isLong: true,
      collateral: BigInt(0),
      positionSize: BigInt(0),
      entryPI: BigInt(0),
      entryPrice: BigInt(0),
      leverage: BigInt(0),
      currentPI: BigInt(0),
      pnl: BigInt(0),
      borrowFees: BigInt(0),
      fundingAccrued: BigInt(0),
      equity: BigInt(0),
      isOpen: true,
    }));
    setPositions(posData);
  }, [positionIds]);

  useEffect(() => {
    fetchPositionDetails();
  }, [fetchPositionDetails]);

  const demoMarketIds = ['demo-1', 'demo-2'];
  const { prices: livePrices, lastUpdate: priceLastUpdate } = useLivePrices({
    marketIds: demoMarketIds,
    pollingInterval: 30000,
    enabled: true
  });

  const calculatePnL = (isLong: boolean, entryPI: bigint, currentPI: bigint, positionSize: bigint): bigint => {
    const priceDiff = Number(currentPI) - Number(entryPI);
    const direction = isLong ? 1 : -1;
    return BigInt(Math.round(direction * priceDiff * Number(positionSize) / 1e18));
  };

  const createLivePosition = (basePosition: Omit<PositionData, 'currentPI' | 'pnl' | 'equity'>, demoMarketId: string): PositionData => {
    const livePrice = livePrices[demoMarketId];
    const currentPI = livePrice ? BigInt(Math.round(livePrice.pi * 1e18)) : basePosition.entryPI;
    const pnl = calculatePnL(basePosition.isLong, basePosition.entryPI, currentPI, basePosition.positionSize);
    const equity = basePosition.collateral + pnl - basePosition.borrowFees + basePosition.fundingAccrued;

    return {
      ...basePosition,
      currentPI,
      pnl,
      equity
    };
  };

  const baseDemoPositions = [
    {
      id: BigInt(1),
      marketId: 'demo-1' as `0x${string}`,
      marketName: 'SpaceX IPO by Dec 2026',
      isLong: true,
      collateral: BigInt('1000000000000000000000'),
      positionSize: BigInt('5000000000000000000000'),
      entryPI: BigInt('350000000000000000'),
      entryPrice: BigInt('355000000000000000'),
      leverage: BigInt('5000000000000000000'),
      borrowFees: BigInt('12000000000000000000'),
      fundingAccrued: BigInt('-3000000000000000000'),
      isOpen: true,
    },
    {
      id: BigInt(2),
      marketId: 'demo-2' as `0x${string}`,
      marketName: 'US-Iran Ceasefire by Sep 2025',
      isLong: false,
      collateral: BigInt('500000000000000000000'),
      positionSize: BigInt('1500000000000000000000'),
      entryPI: BigInt('280000000000000000'),
      entryPrice: BigInt('275000000000000000'),
      leverage: BigInt('3000000000000000000'),
      borrowFees: BigInt('5000000000000000000'),
      fundingAccrued: BigInt('2000000000000000000'),
      isOpen: true,
    },
  ];

  const demoPositions: PositionData[] = baseDemoPositions.map((basePos, index) =>
    createLivePosition(basePos, demoMarketIds[index])
  );

  const displayPositions = positions.length > 0 ? positions : (address ? demoPositions : []);

  const handleCloseClick = (positionId: bigint) => {
    setSelectedPositionId(positionId);
    setCloseState('confirming');
    setCloseError('');
    setClosedPositionPnl(null);
    resetWrite();
  };

  const handleConfirmClose = (position: PositionData) => {
    setClosedPositionPnl(position.pnl);
    writeContract({
      address: CONTRACT_ADDRESSES.executionEngine,
      abi: EXECUTION_ENGINE_ABI,
      functionName: 'closePosition',
      args: [position.id],
    });
  };

  const handleCancelClose = () => {
    setSelectedPositionId(null);
    setCloseState('idle');
    setCloseError('');
    resetWrite();
  };

  const computeNetPnl = (pos: PositionData): bigint => {
    return pos.pnl - pos.borrowFees + pos.fundingAccrued;
  };

  const formatPnl = (value: bigint): string => {
    const num = Number(value) / 1e18;
    const prefix = num >= 0 ? '+' : '';
    return `${prefix}$${num.toFixed(2)}`;
  };

  const getPnlColor = (value: bigint): string => {
    if (value > BigInt(0)) return 'text-accent';
    if (value < BigInt(0)) return 'text-danger';
    return 'text-gray-500';
  };

  const formatPrice = (price: bigint): string => {
    return `${(Number(price) / 1e18 * 100).toFixed(1)}c`;
  };

  const formatLeverage = (leverage: bigint): string => {
    return `${(Number(leverage) / 1e18).toFixed(1)}x`;
  };

  const totalEquity = displayPositions.reduce((sum, pos) => sum + Number(pos.equity) / 1e18, 0);
  const totalNetPnl = displayPositions.reduce((sum, pos) => sum + Number(computeNetPnl(pos)) / 1e18, 0);
  const totalCollateral = displayPositions.reduce((sum, pos) => sum + Number(pos.collateral) / 1e18, 0);

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-gray-100">Your Positions</h2>
        <p className="text-gray-500">
          Monitor and manage your active leveraged positions
        </p>
      </div>

      {/* Account Balance Bar */}
      {address && (
        <div className="bg-surface-2 border border-border rounded-lg p-4 flex flex-col space-y-3 md:flex-row md:space-y-0 md:items-center md:justify-between">
          {isLoadingAccountData ? (
            <div className="flex space-x-8">
              <div>
                <span className="text-xs text-gray-500 uppercase tracking-wide">Account Balance</span>
                <Skeleton width="100px" height="24px" />
              </div>
              <div>
                <span className="text-xs text-gray-500 uppercase tracking-wide">Free Collateral</span>
                <Skeleton width="100px" height="24px" />
              </div>
            </div>
          ) : (
            <div className="flex space-x-8">
              <div>
                <span className="text-xs text-gray-500 uppercase tracking-wide">Account Balance</span>
                <p className="text-lg font-bold font-mono text-gray-100">
                  ${accountBalance ? formatWad(accountBalance as bigint) : '0.00'} USDT
                </p>
              </div>
              <div>
                <span className="text-xs text-gray-500 uppercase tracking-wide">Free Collateral</span>
                <p className="text-lg font-bold font-mono text-gray-100">
                  ${freeCollateral ? formatWad(freeCollateral as bigint) : '0.00'} USDT
                </p>
              </div>
            </div>
          )}
          <span className="text-xs text-gray-600">
            Collateral returned to balance on position close
          </span>
        </div>
      )}

      {/* Close Success Banner */}
      {closeState === 'success' && (
        <div className="bg-accent-muted border border-accent/20 rounded-lg p-4">
          <div className="flex items-center justify-between">
            <div>
              <h4 className="font-semibold text-accent">Position Closed Successfully</h4>
              <p className="text-sm text-gray-300">
                {closedPositionPnl !== null && (
                  <>
                    Net PnL: <span className={`font-mono font-bold ${closedPositionPnl >= BigInt(0) ? 'text-accent' : 'text-danger'}`}>
                      {formatPnl(closedPositionPnl)}
                    </span>
                    {' \u2014 '}
                  </>
                )}
                Collateral and PnL settled to your AccountManager balance.
              </p>
            </div>
            <button
              onClick={() => { setCloseState('idle'); setClosedPositionPnl(null); }}
              className="text-accent hover:text-accent-dim text-sm"
            >
              Dismiss
            </button>
          </div>
        </div>
      )}

      {/* Portfolio Summary */}
      {(isLoadingPositions || displayPositions.length > 0) && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          {isLoadingPositions ? (
            <>
              {[1, 2, 3, 4].map((index) => (
                <div key={index} className="bg-surface-1 rounded-lg border border-border p-5">
                  <div className="flex items-center justify-between mb-1">
                    <Skeleton width="60px" height="16px" />
                    <Skeleton width="40px" height="16px" />
                  </div>
                  <Skeleton width="80px" height="32px" className="mb-1" />
                  <Skeleton width="90px" height="14px" />
                </div>
              ))}
            </>
          ) : (
            <>
              <div className="bg-surface-1 rounded-lg border border-border p-5">
                <div className="flex items-center justify-between mb-1">
                  <h3 className="text-xs font-medium text-gray-500 uppercase tracking-wide">Net PnL</h3>
                  <div className="flex items-center">
                    <div className="w-1.5 h-1.5 bg-accent rounded-full animate-pulse"></div>
                    <span className="text-xs text-accent ml-1 font-medium">LIVE</span>
                  </div>
                </div>
                <p className={`text-2xl font-bold font-mono ${totalNetPnl >= 0 ? 'text-accent' : 'text-danger'}`}>
                  {totalNetPnl >= 0 ? '+' : ''}${totalNetPnl.toFixed(2)}
                </p>
                <p className="text-xs text-gray-600 mt-1">After fees & funding</p>
              </div>
              <div className="bg-surface-1 rounded-lg border border-border p-5">
                <div className="flex items-center justify-between mb-1">
                  <h3 className="text-xs font-medium text-gray-500 uppercase tracking-wide">Total Equity</h3>
                  <div className="flex items-center">
                    <div className="w-1.5 h-1.5 bg-accent rounded-full animate-pulse"></div>
                    <span className="text-xs text-accent ml-1 font-medium">LIVE</span>
                  </div>
                </div>
                <p className="text-2xl font-bold font-mono text-gray-100">${totalEquity.toFixed(2)}</p>
                <p className="text-xs text-gray-600 mt-1">Collateral + net PnL</p>
              </div>
              <div className="bg-surface-1 rounded-lg border border-border p-5">
                <h3 className="text-xs font-medium text-gray-500 mb-1 uppercase tracking-wide">Locked Collateral</h3>
                <p className="text-2xl font-bold font-mono text-gray-100">${totalCollateral.toFixed(2)}</p>
                <p className="text-xs text-gray-600 mt-1">USDT</p>
              </div>
              <div className="bg-surface-1 rounded-lg border border-border p-5">
                <h3 className="text-xs font-medium text-gray-500 mb-1 uppercase tracking-wide">Active Positions</h3>
                <p className="text-2xl font-bold font-mono text-gray-100">{displayPositions.length}</p>
                <p className="text-xs text-gray-600 mt-1">Open</p>
              </div>
            </>
          )}
        </div>
      )}

      {/* Positions List */}
      <div className="space-y-4">
        {isLoadingPositions ? (
          [1, 2].map((index) => (
            <div key={index} className="bg-surface-1 rounded-lg border border-border p-6">
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center space-x-3 mb-3">
                    <Skeleton width="60px" height="24px" />
                    <Skeleton width="40px" height="24px" />
                    <Skeleton width="200px" height="20px" />
                  </div>

                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-4 text-sm">
                    {[1, 2, 3, 4, 5, 6].map((detailIndex) => (
                      <div key={detailIndex}>
                        <Skeleton width="70px" height="16px" className="mb-1" />
                        <Skeleton width="60px" height="20px" />
                      </div>
                    ))}
                  </div>

                  <div className="mt-3 pt-3 border-t border-border">
                    <div className="flex space-x-6">
                      <Skeleton width="100px" height="14px" />
                      <Skeleton width="80px" height="14px" />
                      <Skeleton width="70px" height="14px" />
                    </div>
                  </div>
                </div>

                <div className="ml-6 flex-shrink-0">
                  <Skeleton width="120px" height="36px" />
                </div>
              </div>
            </div>
          ))
        ) : (
          displayPositions.map((position) => {
          const netPnl = computeNetPnl(position);
          const isClosing = selectedPositionId === position.id;
          const pnlPct = Number(position.collateral) > 0
            ? (Number(netPnl) / Number(position.collateral)) * 100
            : 0;

          return (
            <div
              key={position.id.toString()}
              className={`bg-surface-1 rounded-lg border p-6 transition-all ${
                isClosing ? 'border-danger/40 bg-danger-muted' : 'border-border hover:border-border-light'
              }`}
            >
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center space-x-3 mb-3">
                    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-bold ${
                      position.isLong
                        ? 'bg-accent-muted text-accent border border-accent/20'
                        : 'bg-danger-muted text-danger border border-danger/20'
                    }`}>
                      {position.isLong ? 'LONG' : 'SHORT'}
                    </span>
                    <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-bold font-mono bg-surface-3 text-gray-400 border border-border">
                      {formatLeverage(position.leverage)}
                    </span>
                    <h3 className="text-lg font-semibold text-gray-100">{position.marketName}</h3>
                  </div>

                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-4 text-sm">
                    <div>
                      <p className="text-gray-500 text-xs uppercase tracking-wide">Collateral</p>
                      <p className="font-semibold font-mono text-gray-200">${formatWad(position.collateral)}</p>
                    </div>
                    <div>
                      <p className="text-gray-500 text-xs uppercase tracking-wide">Notional</p>
                      <p className="font-semibold font-mono text-gray-200">${formatWad(position.positionSize)}</p>
                    </div>
                    <div>
                      <p className="text-gray-500 text-xs uppercase tracking-wide">Entry</p>
                      <p className="font-semibold font-mono text-gray-200">{formatPrice(position.entryPrice)}</p>
                    </div>
                    <div>
                      <div className="flex items-center space-x-1">
                        <p className="text-gray-500 text-xs uppercase tracking-wide">Current PI</p>
                        <div className="flex items-center">
                          <div className="w-1.5 h-1.5 bg-accent rounded-full animate-pulse"></div>
                        </div>
                      </div>
                      <p className="font-semibold font-mono text-gray-200">{formatPrice(position.currentPI)}</p>
                    </div>
                    <div>
                      <p className="text-gray-500 text-xs uppercase tracking-wide">Price PnL</p>
                      <p className={`font-semibold font-mono ${getPnlColor(position.pnl)}`}>
                        {formatPnl(position.pnl)}
                      </p>
                    </div>
                    <div>
                      <p className="text-gray-500 text-xs uppercase tracking-wide">Net PnL</p>
                      <p className={`font-semibold font-mono ${getPnlColor(netPnl)}`}>
                        {formatPnl(netPnl)}
                      </p>
                      <p className={`text-xs font-mono ${getPnlColor(netPnl)}`}>
                        {pnlPct >= 0 ? '+' : ''}{pnlPct.toFixed(1)}%
                      </p>
                    </div>
                  </div>

                  <div className="mt-3 pt-3 border-t border-border">
                    <div className="flex flex-col space-y-1 sm:flex-row sm:space-y-0 sm:space-x-4 text-xs text-gray-500">
                      <span>Borrow fees: <span className="font-mono text-danger">-${formatWad(position.borrowFees)}</span></span>
                      <span>Funding: <span className={`font-mono ${position.fundingAccrued >= BigInt(0) ? 'text-accent' : 'text-danger'}`}>
                        {formatPnl(position.fundingAccrued)}
                      </span></span>
                      <span>Equity: <span className="font-mono text-gray-300">${formatWad(position.equity)}</span></span>
                      {priceLastUpdate > 0 && (
                        <span className="text-accent">
                          Updated: {new Date(priceLastUpdate).toLocaleTimeString()}
                        </span>
                      )}
                    </div>
                  </div>
                </div>

                {/* Close actions */}
                <div className="ml-6 flex-shrink-0 w-48">
                  {isClosing && closeState === 'confirming' ? (
                    <div className="space-y-3">
                      <div className="bg-surface-2 border border-danger/20 rounded-lg p-3 text-sm">
                        <p className="font-semibold text-danger mb-2">Close Position?</p>
                        <div className="space-y-1 text-xs">
                          <div className="flex justify-between">
                            <span className="text-gray-500">Collateral returned:</span>
                            <span className="font-mono text-gray-200">${formatWad(position.collateral)}</span>
                          </div>
                          <div className="flex justify-between">
                            <span className="text-gray-500">Est. net PnL:</span>
                            <span className={`font-mono ${getPnlColor(netPnl)}`}>{formatPnl(netPnl)}</span>
                          </div>
                          <div className="flex justify-between border-t border-border pt-1 mt-1">
                            <span className="text-gray-300 font-medium">Est. payout:</span>
                            <span className="font-mono font-medium text-gray-200">${formatWad(position.equity)}</span>
                          </div>
                        </div>
                      </div>
                      <div className="flex space-x-2">
                        <button
                          onClick={() => handleConfirmClose(position)}
                          className="flex-1 bg-danger text-white px-3 py-2 rounded-md text-sm font-semibold hover:bg-danger-dim transition-colors"
                        >
                          Confirm
                        </button>
                        <button
                          onClick={handleCancelClose}
                          className="flex-1 bg-surface-3 text-gray-300 px-3 py-2 rounded-md text-sm font-medium hover:bg-border-light transition-colors"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  ) : isClosing && closeState === 'pending' ? (
                    <div className="text-center py-4">
                      <div className="animate-spin w-6 h-6 border-2 border-accent border-t-transparent rounded-full mx-auto mb-2" />
                      <p className="text-sm text-accent font-medium">Closing...</p>
                      <p className="text-xs text-gray-500">Settling PnL</p>
                    </div>
                  ) : isClosing && closeState === 'error' ? (
                    <div className="space-y-2">
                      <div className="bg-danger-muted border border-danger/20 rounded p-2">
                        <p className="text-xs text-danger font-medium">Close failed</p>
                        <p className="text-xs text-gray-400 truncate">{closeError}</p>
                      </div>
                      <button
                        onClick={handleCancelClose}
                        className="w-full bg-surface-3 text-gray-300 px-3 py-2 rounded-md text-sm font-medium hover:bg-border-light transition-colors"
                      >
                        Dismiss
                      </button>
                    </div>
                  ) : (
                    <div className="space-y-2">
                      <button
                        onClick={() => handleCloseClick(position.id)}
                        className="w-full bg-danger/10 text-danger border border-danger/30 px-4 py-2 rounded-md text-sm font-semibold hover:bg-danger/20 hover:border-danger/50 transition-all"
                      >
                        Close Position
                      </button>
                    </div>
                  )}
                </div>
              </div>
            </div>
          );
        }))}
      </div>

      {/* Empty State */}
      {displayPositions.length === 0 && (
        <div className="space-y-8">
          {!address && (
            <div className="bg-surface-1 rounded-lg border border-border p-6">
              <h3 className="text-lg font-semibold text-gray-100 mb-4">Recent Platform Activity</h3>
              <p className="text-sm text-gray-500 mb-4">Example positions from other traders (live from testnet):</p>

              <div className="space-y-3">
                <div className="flex items-center justify-between py-2 px-3 bg-surface-2 rounded border border-border">
                  <div className="flex items-center space-x-3">
                    <span className="inline-flex items-center px-2 py-1 rounded text-xs font-bold bg-accent-muted text-accent border border-accent/20">LONG</span>
                    <span className="text-sm text-gray-200">SpaceX IPO by Dec 2026</span>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-medium font-mono text-gray-200">$2,450 @ 5.0x</p>
                    <p className="text-xs font-mono text-accent">+$302.40 (+12.3%)</p>
                  </div>
                </div>
                <div className="flex items-center justify-between py-2 px-3 bg-surface-2 rounded border border-border">
                  <div className="flex items-center space-x-3">
                    <span className="inline-flex items-center px-2 py-1 rounded text-xs font-bold bg-danger-muted text-danger border border-danger/20">SHORT</span>
                    <span className="text-sm text-gray-200">US-Iran Ceasefire by Sep 2025</span>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-medium font-mono text-gray-200">$890 @ 3.0x</p>
                    <p className="text-xs font-mono text-danger">-$50.73 (-5.7%)</p>
                  </div>
                </div>
                <div className="flex items-center justify-between py-2 px-3 bg-surface-2 rounded border border-border">
                  <div className="flex items-center space-x-3">
                    <span className="inline-flex items-center px-2 py-1 rounded text-xs font-bold bg-accent-muted text-accent border border-accent/20">LONG</span>
                    <span className="text-sm text-gray-200">FIFA 2026 Final: Brazil Win</span>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-medium font-mono text-gray-200">$1,200 @ 8.0x</p>
                    <p className="text-xs font-mono text-accent">+$346.80 (+28.9%)</p>
                  </div>
                </div>
              </div>

              <p className="text-xs text-gray-600 mt-4 text-center">
                Connect wallet to view your own positions
              </p>
            </div>
          )}

          {address && (
            <div className="text-center py-12">
              <div className="w-16 h-16 bg-surface-3 rounded-full flex items-center justify-center mx-auto mb-4">
                <svg className="w-8 h-8 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                </svg>
              </div>
              <h3 className="text-lg font-medium text-gray-200 mb-2">No Open Positions</h3>
              <p className="text-gray-500 mb-2">You don't have any active positions yet.</p>
              <p className="text-sm text-gray-600">Go to Markets to find an opportunity, then open a position from Trading.</p>
            </div>
          )}
        </div>
      )}

      {/* Trade History Section */}
      <div className="mt-12">
        <TradeHistory />
      </div>
    </div>
  );
};

export default Positions;
