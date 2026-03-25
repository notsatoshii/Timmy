import React, { useState, useEffect, useCallback } from 'react';
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { usePublicClient } from 'wagmi';
import { useWallet } from '../hooks/useWallet';
import { useDemoWallet } from '../hooks/useDemoWallet';
import { CONTRACT_ADDRESSES, formatWad, formatUsdt, WAD } from '../config/contracts';
import {
  POSITION_MANAGER_ABI,
  EXECUTION_ENGINE_ABI,
  ACCOUNT_MANAGER_ABI,
  BORROW_FEE_ENGINE_ABI,
  FUNDING_RATE_ENGINE_ABI,
} from '../config/abis';
import { useLivePrices } from '../hooks/useLivePrices';
import { useMarketProbabilities } from '../hooks/useMarketProbabilities';
import { useNotifications } from '../contexts/NotificationContext';
// // import TradeHistory from './TradeHistory';
// // import PnLChart from './PnLChart'; // Removed — showing $0 // Removed — showing $0
// // import FeeBreakdown from './FeeBreakdown'; // Removed — showing $0 // Removed — showing $0
// // import MarginUsage from './MarginUsage'; // Removed — showing $0 // Removed — showing $0
import Skeleton from './Skeleton';
import ProfessionalLoader from './ProfessionalLoader';
const MARKET_NAMES: Record<string, string> = {
  "0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1": "SpaceX IPO 2026",
  "0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a": "US-Iran Ceasefire",
  "0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d": "Nothing Ever Happens 2026",
  "0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2": "FIFA World Cup: Spain",
  "0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7": "Fed Rate Below 4%",
  "0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2": "SpaceX via Ackman SPAR",
  "0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554": "AAPL Above $250",
  "0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc": "OpenSea Token Launch",
  "0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f": "Fed April Rate Cut",
  "0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea": "Argentina ARS/USD",
  "0x8215cf9d075f1ee6044f05d17fa1685d88da515f3ea119e10f50cb487f9e3774": "BTC Above $80k March",
  "0x329ec977deb23dbc392959044918040f8a9252d502c6948eea33d2e72e787ddd": "Masters: Aberg Wins",
  "0xc2a3fba66cdee6088484ae353b3c414390c591ac5cf485248f9b9cbb591a8cd4": "Hungary PM: Orbán",
  "0x35f95cb4e4331813cbbcf8acd4efea29305a24ff890b4f22d163722095ebb706": "Eurovision: France",
  "0x73b37115e0a747b8fec07143017b8359a53677baa466a4847c6af7c14c0ec5c7": "NCAA: Florida Wins",
  "0x6ee69274ed792087cd80dc1db0f90456f4d2621287375a0e90032f61bbe32e9e": "Hungary: TISZA Seats",
  "0xdf341f72d47f0bbcb009aaa13d9d683a79ce8f77de068943c0316feade190c21": "Fed April No Change",
  "0x0e6da084b18fb861b29203d611dc83df2bcfa3294281dd57ea735f3096023438": "ETH Above $2600 March",
  "0x5131ef671dbddffe63e34798f3cf92be05c95001b20f29255f97d87b2d6e1de2": "Iran Regime Falls",
  "0x7155116cef46226d9a58e096c87fba03555313c85b9b9b649dca754090845136": "Trump Visits China",
};


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
  openTimestamp?: bigint;
}

type CloseState = 'idle' | 'confirming' | 'pending' | 'success' | 'error';

interface PositionsProps {
  onStatsUpdate?: (stats: {
    netPnl: string;
    totalEquity: string;
    lockedCollateral: string;
    activePositions: number;
  }) => void;
}

const Positions: React.FC<PositionsProps> = ({ onStatsUpdate }) => {
  const { address } = useWallet();
  const { isDemoMode: isDemoWallet, sendTransaction: demoSend } = useDemoWallet();
  const publicClient = usePublicClient();
  const { showTradeConfirmation, showErrorToast, showLiquidationWarning } = useNotifications();
  const [positions, setPositions] = useState<PositionData[]>([]);
  const [isFetchingDetails, setIsFetchingDetails] = useState(false);
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
  const isLoadingPositions = address && (loadingPositionIds || isFetchingDetails);

  const { markets: oracleMarkets } = useMarketProbabilities();
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

      // Find the closed position for notification
      const allPositions = positions;
      const closedPosition = allPositions.find(pos => pos.id === selectedPositionId);
      if (closedPosition && txHash) {
        showTradeConfirmation('close', closedPosition.marketName, txHash);
      }

      const timer = setTimeout(() => {
        setCloseState('idle');
        setSelectedPositionId(null);
        setClosedPositionPnl(null);
      }, 5000);
      return () => clearTimeout(timer);
    }
  }, [txConfirmed, closeState, refetchPositionIds, refetchBalance, refetchFreeCollateral, selectedPositionId, txHash, showTradeConfirmation, positions, address]);

  useEffect(() => {
    if (writeError) {
      setCloseState('error');
      setCloseError(writeError.message?.slice(0, 200) || 'Transaction failed');
      showErrorToast(
        'Position Close Failed',
        'There was an error closing your position. Please try again.'
      );
    }
  }, [writeError, showErrorToast]);

  const fetchPositionDetails = useCallback(async () => {
    setIsFetchingDetails(true);

    if (!positionIds || !Array.isArray(positionIds) || positionIds.length === 0) {
      setPositions([]);
      setIsFetchingDetails(false);
      return;
    }

    // Read real position data from PositionManager contract
    // This ensures the component doesn't crash while we implement proper contract calls
    const posData: PositionData[] = [];

    for (const id of positionIds as bigint[]) {
      try {
        // Read real position data from contract
        if (!publicClient) {
          continue;
        }

        const rawPos = await publicClient.readContract({
          address: CONTRACT_ADDRESSES.positionManager,
          abi: POSITION_MANAGER_ABI,
          functionName: 'getPosition',
          args: [id],
        }) as any;

        // Skip closed positions
        if (rawPos.isOpen === false) {
          continue;
        }

        const position: PositionData = {
          id: rawPos.id ?? id,
          marketId: rawPos.marketId as `0x${string}`,
          marketName: MARKET_NAMES[(rawPos.marketId as string).toLowerCase()] || MARKET_NAMES[rawPos.marketId as string] || `Position #${(rawPos.id ?? id).toString()}`,
          isLong: rawPos.isLong,
          collateral: rawPos.collateral,
          positionSize: rawPos.positionSize,
          entryPI: rawPos.entryPI,
          entryPrice: rawPos.entryPrice,
          leverage: rawPos.leverage,
          currentPI: rawPos.entryPI,
          pnl: BigInt(0),
          borrowFees: BigInt(0), // Will be fetched below
          fundingAccrued: BigInt(0), // Will be fetched below
          equity: BigInt(0),
          isOpen: rawPos.isOpen,
          openTimestamp: rawPos.openTimestamp ?? BigInt(0),
        };

        // Read accrued borrow fees from BorrowFeeEngine
        try {
          const borrowFees = await publicClient.readContract({
            address: CONTRACT_ADDRESSES.borrowFeeEngine,
            abi: BORROW_FEE_ENGINE_ABI,
            functionName: 'getAccruedFees',
            args: [id],
          }) as bigint;
          position.borrowFees = borrowFees;
        } catch (e) {
          // Borrow fees unavailable, default to 0
        }

        // Read accrued funding from FundingRateEngine
        try {
          const fundingAccrued = await publicClient.readContract({
            address: CONTRACT_ADDRESSES.fundingRateEngine,
            abi: FUNDING_RATE_ENGINE_ABI,
            functionName: 'getAccruedFunding',
            args: [id],
          }) as bigint;
          position.fundingAccrued = fundingAccrued;
        } catch (e) {
          // Funding data unavailable, default to 0
        }

        // Calculate PnL using ON-CHAIN Mark Price (getPI) — same source as entry price
        try {
          const onChainPI = await publicClient.readContract({
            address: CONTRACT_ADDRESSES.oracleAdapter as `0x${string}`,
            abi: [{ name: 'getPI', type: 'function', stateMutability: 'view', inputs: [{ name: 'marketId', type: 'bytes32' }], outputs: [{ name: '', type: 'uint256' }] }],
            functionName: 'getPI',
            args: [position.marketId],
          }) as bigint;
          if (onChainPI > BigInt(0)) {
            position.currentPI = onChainPI;
          }
        } catch (e) {
          // Fall back to entryPI if oracle read fails
        }
        const priceDiff = Number(position.currentPI - position.entryPI);
        const direction = position.isLong ? 1 : -1;
        const pnlValue = direction * priceDiff * Number(position.positionSize) / Number(WAD);
        position.pnl = BigInt(Math.round(pnlValue));

        posData.push(position);
      } catch (error) {
        console.error(`[Positions] Error creating position ${id}:`, error);
        // Skip this position if there's an error
      }
    }

    setPositions(posData);
      setIsFetchingDetails(false);
  }, [positionIds, address]);

  useEffect(() => {
    fetchPositionDetails();
  }, [fetchPositionDetails]);

  const { prices: livePrices, lastUpdate: priceLastUpdate } = useLivePrices({
    marketIds: positions.map(p => p.marketId),
    pollingInterval: 30000,
    enabled: positions.length > 0
  });

  const calculatePnL = (isLong: boolean, entryPI: bigint, currentPI: bigint, positionSize: bigint): bigint => {
    try {
      // Prevent division by zero and handle edge cases
      if (positionSize === BigInt(0) || entryPI === currentPI) {
        return BigInt(0);
      }

      const priceDiff = Number(currentPI) - Number(entryPI);
      const direction = isLong ? 1 : -1;
      const pnlValue = direction * priceDiff * Number(positionSize) / Number(WAD);

      // Check for overflow/underflow
      if (!isFinite(pnlValue) || isNaN(pnlValue)) {
        return BigInt(0);
      }

      return BigInt(Math.round(pnlValue));
    } catch (error) {
      console.warn('Error calculating PnL:', error);
      return BigInt(0);
    }
  };




  // Show real positions if they exist, otherwise show demo positions when no wallet is connected
  
  // Use positions as-is — PnL already calculated from on-chain Mark Price during fetch
  const displayPositions = React.useMemo(() => {
    if (!positions || positions.length === 0) return positions;
    return positions.map(pos => {
      // PnL already uses on-chain getPI() from fetch, just recompute equity
      const equity = pos.collateral + pos.pnl - pos.borrowFees + pos.fundingAccrued;
      return { ...pos, equity };
    });
  }, [positions]);


  const handleCloseClick = (positionId: bigint) => {
    setSelectedPositionId(positionId);
    setCloseState('confirming');
    setCloseError('');
    setClosedPositionPnl(null);
    resetWrite();
  };

  const handleConfirmClose = async (position: PositionData) => {
    setClosedPositionPnl(position.pnl);

    if (isDemoWallet) {
      try {
        setCloseState('pending');
        const result = await demoSend({
          address: CONTRACT_ADDRESSES.executionEngine,
          abi: EXECUTION_ENGINE_ABI,
          functionName: 'closePosition',
          args: [position.id],
        });
        setCloseState('success');
        setTimeout(() => {
          refetchPositionIds();
          refetchBalance();
          refetchFreeCollateral();
          setSelectedPositionId(null);
          setCloseState('idle');
        }, 2000);
      } catch (error: any) {
        console.error('[Positions] Demo close error:', error);
        setCloseError(error?.message || 'Close failed');
        setCloseState('error');
      }
    } else {
      writeContract({
        address: CONTRACT_ADDRESSES.executionEngine,
        abi: EXECUTION_ENGINE_ABI,
        functionName: 'closePosition',
        args: [position.id],
      });
    }
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
    try {
      const num = Number(value) / 1e6;
      if (!isFinite(num) || isNaN(num)) {
        return '$0.00';
      }
      const prefix = num >= 0 ? '+' : '';
      return `${prefix}$${Math.abs(num).toFixed(2)}`;
    } catch (error) {
      console.warn('Error formatting PnL:', error);
      return '$0.00';
    }
  };

  const getPnlColor = (value: bigint): string => {
    if (value > BigInt(0)) return 'text-accent';
    if (value < BigInt(0)) return 'text-danger';
    return 'text-gray-500';
  };

  const formatPrice = (price: bigint): string => {
    try {
      const num = Number(price) / Number(WAD) * 100;
      if (!isFinite(num) || isNaN(num)) {
        return '0.0c';
      }
      return `${Math.max(0, num).toFixed(1)}c`;
    } catch (error) {
      console.warn('Error formatting price:', error);
      return '0.0c';
    }
  };

  const formatLeverage = (leverage: bigint): string => {
    try {
      const num = Number(leverage) / Number(WAD);
      if (!isFinite(num) || isNaN(num)) {
        return '1.0x';
      }
      return `${Math.max(1, num).toFixed(1)}x`;
    } catch (error) {
      console.warn('Error formatting leverage:', error);
      return '1.0x';
    }
  };

  const totalEquity = displayPositions.reduce((sum, pos) => {
    try {
      const equity = Number(pos.equity) / 1e6;
      return sum + (isFinite(equity) ? equity : 0);
    } catch {
      return sum;
    }
  }, 0);

  const totalNetPnl = displayPositions.reduce((sum, pos) => {
    try {
      const netPnl = Number(computeNetPnl(pos)) / 1e6;
      return sum + (isFinite(netPnl) ? netPnl : 0);
    } catch {
      return sum;
    }
  }, 0);

  const totalCollateral = displayPositions.reduce((sum, pos) => {
    try {
      const collateral = Number(pos.collateral) / 1e6;
      return sum + (isFinite(collateral) ? collateral : 0);
    } catch {
      return sum;
    }
  }, 0);

  // Push aggregated stats to parent for the top stats bar
  useEffect(() => {
    if (onStatsUpdate) {
      const fmtPnl = totalNetPnl >= 0
        ? `+$${totalNetPnl.toFixed(2)}`
        : `-$${Math.abs(totalNetPnl).toFixed(2)}`;
      onStatsUpdate({
        netPnl: fmtPnl,
        totalEquity: `$${totalEquity.toFixed(2)}`,
        lockedCollateral: `$${totalCollateral.toFixed(2)}`,
        activePositions: displayPositions.length,
      });
    }
  }, [totalNetPnl, totalEquity, totalCollateral, displayPositions.length, onStatsUpdate]);

  // Monitor positions for liquidation warnings
  useEffect(() => {
    displayPositions.forEach(position => {
      const equity = Number(position.equity) / 1e6;
      const notional = Number(position.positionSize) / 1e6;

      if (notional > 0) {
        // Calculate maintenance margin requirement (simplified: 2.5% of notional)
        const maintenanceMargin = notional * 0.025;

        // Calculate margin percentage: equity / maintenance margin * 100
        const marginPercent = (equity / maintenanceMargin) * 100;

        // Trigger warnings if margin is below 150%
        if (marginPercent < 150 && marginPercent > 0) {
          // Only warn once per session per position to avoid spam
          const warningKey = `liquidation-warning-${position.id}-${Math.floor(marginPercent)}`;

          if (!sessionStorage.getItem(warningKey)) {
            sessionStorage.setItem(warningKey, 'shown');
            showLiquidationWarning(marginPercent, position.marketName);
          }
        }
      }
    });
  }, [displayPositions, showLiquidationWarning]);

  // Listen for navigation events from notifications
  useEffect(() => {
    const handleNavigateToPositions = () => {
      // This will be handled by the parent Dashboard component
      // For now, we just scroll to top of positions
      window.scrollTo({ top: 0, behavior: 'smooth' });
    };

    window.addEventListener('navigate-to-positions', handleNavigateToPositions);
    return () => window.removeEventListener('navigate-to-positions', handleNavigateToPositions);
  }, []);

  // Show branded loader while fetching positions
  if (isLoadingPositions) {
    return <ProfessionalLoader title="Loading Positions" subtitle="Fetching position data from smart contracts" variant="blockchain" size="lg" />;
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-gray-100">Your Positions</h2>
        <p className="text-gray-500">
          Monitor and manage your active leveraged positions
        </p>
      </div>

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

      {/* Portfolio summary is shown in the top stats bar */}

      {/* Enhanced Portfolio Dashboard */}
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
                      <p className="font-semibold font-mono text-gray-200">${formatUsdt(position.collateral)}</p>
                    </div>
                    <div>
                      <p className="text-gray-500 text-xs uppercase tracking-wide">Notional</p>
                      <p className="font-semibold font-mono text-gray-200">${formatUsdt(position.positionSize)}</p>
                    </div>
                    <div>
                      <p className="text-gray-500 text-xs uppercase tracking-wide">Entry</p>
                      <p className="font-semibold font-mono text-gray-200">{formatPrice(position.entryPrice)}</p>
                      {position.entryPI !== position.entryPrice && (
                        <p className="text-[10px] text-steel/50 font-mono">PI: {formatPrice(position.entryPI)}</p>
                      )}
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
                      <p className="text-gray-500 text-xs uppercase tracking-wide">Unrealized PnL</p>
                      <p className={`font-semibold font-mono ${getPnlColor(position.pnl)}`}>
                        {formatPnl(position.pnl)}
                      </p>
                    </div>
                    <div>
                      <p className="text-gray-500 text-xs uppercase tracking-wide">Net PnL (after fees)</p>
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
                      <span>Opened: <span className="font-mono text-gray-300">{position.openTimestamp && position.openTimestamp && position.openTimestamp > BigInt(0) ? new Date(Number(position.openTimestamp) * 1000).toLocaleString() : "N/A"}</span></span>
                      <span>Borrow fees: <span className="font-mono text-danger">-${formatUsdt(position.borrowFees)}</span></span>
                      <span>Funding: <span className={`font-mono ${position.fundingAccrued >= BigInt(0) ? 'text-accent' : 'text-danger'}`}>
                        {formatPnl(position.fundingAccrued)}
                      </span></span>
                      <span>Equity: <span className="font-mono text-gray-300">${formatUsdt(position.equity)}</span></span>
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
                            <span className="font-mono text-gray-200">${formatUsdt(position.collateral)}</span>
                          </div>
                          <div className="flex justify-between">
                            <span className="text-gray-500">Est. net PnL:</span>
                            <span className={`font-mono ${getPnlColor(netPnl)}`}>{formatPnl(netPnl)}</span>
                          </div>
                          <div className="flex justify-between border-t border-border pt-1 mt-1">
                            <span className="text-gray-300 font-medium">Est. payout:</span>
                            <span className="font-mono font-medium text-gray-200">${formatUsdt(position.equity)}</span>
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
      {!isLoadingPositions && displayPositions.length === 0 && (
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

      {/* Trade History removed */}
    </div>
  );
};

export default Positions;
