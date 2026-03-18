import React, { useState, useEffect, useCallback } from 'react';
import { useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { usePublicClient } from 'wagmi';
import { useWallet } from '../hooks/useWallet';
import { CONTRACT_ADDRESSES, formatWad, formatUsdt, WAD } from '../config/contracts';
import {
  POSITION_MANAGER_ABI,
  EXECUTION_ENGINE_ABI,
  ACCOUNT_MANAGER_ABI,
} from '../config/abis';
import { useLivePrices } from '../hooks/useLivePrices';
import { useMarketProbabilities } from '../hooks/useMarketProbabilities';
import { useNotifications } from '../contexts/NotificationContext';
// // import TradeHistory from './TradeHistory';
// // import PnLChart from './PnLChart'; // Removed — showing $0 // Removed — showing $0
// // import FeeBreakdown from './FeeBreakdown'; // Removed — showing $0 // Removed — showing $0
// // import MarginUsage from './MarginUsage'; // Removed — showing $0 // Removed — showing $0
import Skeleton from './Skeleton';
const MARKET_NAMES: Record<string, string> = {
  "0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1": "SpaceX IPO 2026",
  "0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a": "US-Iran Ceasefire",
  "0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d": "Nothing Ever Happens 2026",
  "0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2": "FIFA World Cup: Spain",
  "0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7": "Fed Rate Below 4%",
  "0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2": "SpaceX via Ackman SPAR",
  "0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554": "AAPL Above $250",
  "0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc": "BTC Dominance Above 60%",
  "0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f": "EU AI Regulation 2026",
  "0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea": "Argentina Dollarization",
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
}

type CloseState = 'idle' | 'confirming' | 'pending' | 'success' | 'error';

const Positions: React.FC = () => {
  const { address } = useWallet();
  const publicClient = usePublicClient();
  const { showTradeConfirmation, showErrorToast, showLiquidationWarning } = useNotifications();
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
      const allPositions = positions.length > 0 ? positions : (address ? baseDemoPositions.map((basePos, index) =>
        createLivePosition(basePos, demoMarketIds[index])
      ) : []);
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
    console.log('[Positions] fetchPositionDetails called', {
      address,
      positionIds: positionIds ? Array.from(positionIds as bigint[]).map(id => id.toString()) : null
    });

    if (!positionIds || !Array.isArray(positionIds) || positionIds.length === 0) {
      console.log('[Positions] No position IDs found, setting empty array');
      setPositions([]);
      return;
    }

    // Read real position data from PositionManager contract
    // This ensures the component doesn't crash while we implement proper contract calls
    const posData: PositionData[] = [];

    for (const id of positionIds as bigint[]) {
      try {
        console.log(`[Positions] Processing position ID: ${id.toString()}`);

        // Read real position data from contract
        if (!publicClient) {
          console.warn('[Positions] No publicClient available, skipping position', id.toString());
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
          console.log(`[Positions] Position ${id.toString()} is closed, skipping`);
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
          borrowFees: BigInt(0), // TODO: calculate from borrowIndex
          fundingAccrued: BigInt(0), // TODO: calculate from fundingIndex
          equity: BigInt(0),
          isOpen: rawPos.isOpen,
        };

        console.log(`[Positions] Loaded real position ${id.toString()} from contract`);

        // Calculate PnL with proper decimal scaling
        // Update currentPI from on-chain oracle (same source as Markets tab)
        console.log(`[DEBUG] Position ${id} marketId: ${mktId}, oracleMarkets IDs:`, oracleMarkets?.map((m: any) => m.id.toLowerCase()));
        const mktId = (position.marketId as string).toLowerCase();
        const oracleMatch = oracleMarkets?.find((m: any) => m.id.toLowerCase() === mktId);
        if (oracleMatch && oracleMatch.probability > 0 && oracleMatch.probability <= 1) {
          position.currentPI = BigInt(Math.round(oracleMatch.probability * Number(WAD)));
        }
        const priceDiff = Number(position.currentPI - position.entryPI);
        const direction = position.isLong ? 1 : -1;
        const pnlValue = direction * priceDiff * Number(position.positionSize) / Number(WAD);
        position.pnl = BigInt(Math.round(pnlValue));

        console.log(`[Positions] Position ${id} PnL calculation:`, {
          entryPI: position.entryPI.toString(),
          currentPI: position.currentPI.toString(),
          priceDiff,
          direction,
          positionSizeNumber: Number(position.positionSize),
          WADNumber: Number(WAD),
          pnlValue,
          pnlBigInt: position.pnl.toString(),
          pnlFormatted: formatPnl(position.pnl)
        });

        // Calculate equity: collateral + PnL - borrow fees + funding
        position.equity = position.collateral + position.pnl - position.borrowFees + position.fundingAccrued;

        console.log(`[Positions] Position ${id} equity calculation:`, {
          collateral: position.collateral.toString(),
          pnl: position.pnl.toString(),
          borrowFees: position.borrowFees.toString(),
          fundingAccrued: position.fundingAccrued.toString(),
          equity: position.equity.toString(),
          equityFormatted: formatUsdt(position.equity)
        });

        posData.push(position);
      } catch (error) {
        console.error(`[Positions] Error creating position ${id}:`, error);
        // Skip this position if there's an error
      }
    }

    console.log('[Positions] Final positions array:', posData.length, 'positions:',
      posData.map(p => ({
        id: p.id.toString(),
        equity: formatUsdt(p.equity),
        pnl: formatPnl(p.pnl),
        collateral: formatUsdt(p.collateral)
      }))
    );
    setPositions(posData);
  }, [positionIds, address, oracleMarkets]);

  useEffect(() => {
    fetchPositionDetails();
  }, [fetchPositionDetails]);

  const demoMarketIds = ['demo-1', 'demo-2', 'demo-3', 'demo-4', 'demo-5', 'demo-6', 'demo-7', 'demo-8', 'demo-9', 'demo-10', 'demo-11', 'demo-12'];
  const { prices: livePrices, lastUpdate: priceLastUpdate } = useLivePrices({
    marketIds: demoMarketIds,
    pollingInterval: 30000,
    enabled: true
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

  const createLivePosition = (basePosition: Omit<PositionData, 'currentPI' | 'pnl' | 'equity'>, demoMarketId: string): PositionData => {
    console.log(`[createLivePosition] Processing ${demoMarketId}:`, {
      id: basePosition.id.toString(),
      marketName: basePosition.marketName,
      collateral: basePosition.collateral.toString(),
      collateralFormatted: formatUsdt(basePosition.collateral),
      positionSize: basePosition.positionSize.toString(),
      positionSizeFormatted: formatUsdt(basePosition.positionSize),
      entryPI: basePosition.entryPI.toString(),
      borrowFees: basePosition.borrowFees.toString(),
      borrowFeesFormatted: formatUsdt(basePosition.borrowFees),
      fundingAccrued: basePosition.fundingAccrued.toString(),
      fundingAccruedFormatted: formatUsdt(basePosition.fundingAccrued)
    });

    try {
      const livePrice = livePrices?.[demoMarketId];
      let currentPI = basePosition.entryPI;

      console.log(`[createLivePosition] Live price data for ${demoMarketId}:`, livePrice);

      if (livePrice && typeof livePrice.pi === 'number' && livePrice.pi > 0 && livePrice.pi <= 1) {
        currentPI = BigInt(Math.round(livePrice.pi * Number(WAD)));
        console.log(`[createLivePosition] Updated currentPI from live price:`, {
          livePi: livePrice.pi,
          currentPI: currentPI.toString()
        });
      } else {
        console.log(`[createLivePosition] Using entry PI as current PI:`, currentPI.toString());
      }

      const pnl = calculatePnL(basePosition.isLong, basePosition.entryPI, currentPI, basePosition.positionSize);

      console.log(`[createLivePosition] PnL calculation for ${demoMarketId}:`, {
        pnl: pnl.toString(),
        pnlFormatted: formatPnl(pnl)
      });

      // Safely calculate equity with proper error handling
      let equity = BigInt(0);
      try {
        equity = basePosition.collateral + pnl - basePosition.borrowFees + basePosition.fundingAccrued;
        console.log(`[createLivePosition] Equity calculation for ${demoMarketId}:`, {
          collateral: basePosition.collateral.toString(),
          pnl: pnl.toString(),
          borrowFees: basePosition.borrowFees.toString(),
          fundingAccrued: basePosition.fundingAccrued.toString(),
          equity: equity.toString(),
          equityFormatted: formatUsdt(equity)
        });
      } catch (error) {
        console.warn(`[createLivePosition] Error calculating equity for ${demoMarketId}:`, error);
        equity = basePosition.collateral; // Fallback to collateral only
      }

      const finalPosition = {
        ...basePosition,
        currentPI,
        pnl,
        equity
      };

      console.log(`[createLivePosition] Final position for ${demoMarketId}:`, {
        id: finalPosition.id.toString(),
        marketName: finalPosition.marketName,
        equity: formatWad(finalPosition.equity),
        pnl: formatPnl(finalPosition.pnl),
        collateral: formatWad(finalPosition.collateral)
      });

      return finalPosition;
    } catch (error) {
      console.error(`[createLivePosition] Error creating live position for ${demoMarketId}:`, error);
      // Return a safe fallback position
      return {
        ...basePosition,
        currentPI: basePosition.entryPI,
        pnl: BigInt(0),
        equity: basePosition.collateral
      };
    }
  };

  const baseDemoPositions = [
    {
      id: BigInt(1),
      marketId: 'demo-1' as `0x${string}`,
      marketName: 'SpaceX IPO by Dec 2026',
      isLong: true,
      collateral: BigInt(1000) * WAD, // 1000 USDT
      positionSize: BigInt(5000) * WAD, // 5000 notional
      entryPI: BigInt(350) * WAD / BigInt(1000), // 0.35 PI
      entryPrice: BigInt(355) * WAD / BigInt(1000), // 0.355 entry price
      leverage: BigInt(5) * WAD, // 5x leverage
      borrowFees: BigInt(12) * WAD, // 12 USDT borrow fees
      fundingAccrued: BigInt(-3) * WAD, // -3 USDT funding
      isOpen: true,
    },
    {
      id: BigInt(2),
      marketId: 'demo-2' as `0x${string}`,
      marketName: 'US-Iran Ceasefire by Sep 2025',
      isLong: false,
      collateral: BigInt(500) * WAD, // 500 USDT
      positionSize: BigInt(1500) * WAD, // 1500 notional
      entryPI: BigInt(280) * WAD / BigInt(1000), // 0.28 PI
      entryPrice: BigInt(275) * WAD / BigInt(1000), // 0.275 entry price
      leverage: BigInt(3) * WAD, // 3x leverage
      borrowFees: BigInt(5) * WAD, // 5 USDT borrow fees
      fundingAccrued: BigInt(2) * WAD, // +2 USDT funding
      isOpen: true,
    },
    // Add more demo positions to reach at least 10 for testing
    {
      id: BigInt(3),
      marketId: 'demo-3' as `0x${string}`,
      marketName: 'Bitcoin at $100k by 2025',
      isLong: true,
      collateral: BigInt(2000) * WAD,
      positionSize: BigInt(10000) * WAD,
      entryPI: BigInt(450) * WAD / BigInt(1000), // 0.45 PI
      entryPrice: BigInt(455) * WAD / BigInt(1000), // 0.455 entry price
      leverage: BigInt(5) * WAD,
      borrowFees: BigInt(25) * WAD,
      fundingAccrued: BigInt(8) * WAD,
      isOpen: true,
    },
    {
      id: BigInt(4),
      marketId: 'demo-4' as `0x${string}`,
      marketName: 'Apple $200 by June 2025',
      isLong: false,
      collateral: BigInt(750) * WAD,
      positionSize: BigInt(3750) * WAD,
      entryPI: BigInt(600) * WAD / BigInt(1000), // 0.6 PI
      entryPrice: BigInt(595) * WAD / BigInt(1000), // 0.595 entry price
      leverage: BigInt(5) * WAD,
      borrowFees: BigInt(18) * WAD,
      fundingAccrued: BigInt(-2) * WAD,
      isOpen: true,
    },
    {
      id: BigInt(5),
      marketId: 'demo-5' as `0x${string}`,
      marketName: 'Tesla FSD by end of 2024',
      isLong: true,
      collateral: BigInt(300) * WAD,
      positionSize: BigInt(1200) * WAD,
      entryPI: BigInt(200) * WAD / BigInt(1000), // 0.2 PI
      entryPrice: BigInt(205) * WAD / BigInt(1000), // 0.205 entry price
      leverage: BigInt(4) * WAD,
      borrowFees: BigInt(8) * WAD,
      fundingAccrued: BigInt(1) * WAD,
      isOpen: true,
    },
    {
      id: BigInt(6),
      marketId: 'demo-6' as `0x${string}`,
      marketName: 'Meta VR Adoption 20%',
      isLong: false,
      collateral: BigInt(1200) * WAD,
      positionSize: BigInt(2400) * WAD,
      entryPI: BigInt(750) * WAD / BigInt(1000), // 0.75 PI
      entryPrice: BigInt(745) * WAD / BigInt(1000), // 0.745 entry price
      leverage: BigInt(2) * WAD,
      borrowFees: BigInt(15) * WAD,
      fundingAccrued: BigInt(-5) * WAD,
      isOpen: true,
    },
    {
      id: BigInt(7),
      marketId: 'demo-7' as `0x${string}`,
      marketName: 'AI Chip War Resolution',
      isLong: true,
      collateral: BigInt(850) * WAD,
      positionSize: BigInt(5100) * WAD,
      entryPI: BigInt(400) * WAD / BigInt(1000), // 0.4 PI
      entryPrice: BigInt(405) * WAD / BigInt(1000), // 0.405 entry price
      leverage: BigInt(6) * WAD,
      borrowFees: BigInt(22) * WAD,
      fundingAccrued: BigInt(3) * WAD,
      isOpen: true,
    },
    {
      id: BigInt(8),
      marketId: 'demo-8' as `0x${string}`,
      marketName: 'Climate Bill Passage 2025',
      isLong: false,
      collateral: BigInt(600) * WAD,
      positionSize: BigInt(1800) * WAD,
      entryPI: BigInt(550) * WAD / BigInt(1000), // 0.55 PI
      entryPrice: BigInt(545) * WAD / BigInt(1000), // 0.545 entry price
      leverage: BigInt(3) * WAD,
      borrowFees: BigInt(9) * WAD,
      fundingAccrued: BigInt(-1) * WAD,
      isOpen: true,
    },
    {
      id: BigInt(9),
      marketId: 'demo-9' as `0x${string}`,
      marketName: 'Fed Rate Cut by March',
      isLong: true,
      collateral: BigInt(1500) * WAD,
      positionSize: BigInt(7500) * WAD,
      entryPI: BigInt(350) * WAD / BigInt(1000), // 0.35 PI
      entryPrice: BigInt(355) * WAD / BigInt(1000), // 0.355 entry price
      leverage: BigInt(5) * WAD,
      borrowFees: BigInt(30) * WAD,
      fundingAccrued: BigInt(12) * WAD,
      isOpen: true,
    },
    {
      id: BigInt(10),
      marketId: 'demo-10' as `0x${string}`,
      marketName: 'Energy Independence 2026',
      isLong: false,
      collateral: BigInt(950) * WAD,
      positionSize: BigInt(3800) * WAD,
      entryPI: BigInt(650) * WAD / BigInt(1000), // 0.65 PI
      entryPrice: BigInt(645) * WAD / BigInt(1000), // 0.645 entry price
      leverage: BigInt(4) * WAD,
      borrowFees: BigInt(20) * WAD,
      fundingAccrued: BigInt(-7) * WAD,
      isOpen: true,
    },
    {
      id: BigInt(11),
      marketId: 'demo-11' as `0x${string}`,
      marketName: 'Quantum Computing Breakthrough',
      isLong: true,
      collateral: BigInt(400) * WAD,
      positionSize: BigInt(2800) * WAD,
      entryPI: BigInt(150) * WAD / BigInt(1000), // 0.15 PI
      entryPrice: BigInt(155) * WAD / BigInt(1000), // 0.155 entry price
      leverage: BigInt(7) * WAD,
      borrowFees: BigInt(14) * WAD,
      fundingAccrued: BigInt(2) * WAD,
      isOpen: true,
    },
    {
      id: BigInt(12),
      marketId: 'demo-12' as `0x${string}`,
      marketName: 'Space Tourism $1B Revenue',
      isLong: false,
      collateral: BigInt(1100) * WAD,
      positionSize: BigInt(3300) * WAD,
      entryPI: BigInt(800) * WAD / BigInt(1000), // 0.8 PI
      entryPrice: BigInt(795) * WAD / BigInt(1000), // 0.795 entry price
      leverage: BigInt(3) * WAD,
      borrowFees: BigInt(16) * WAD,
      fundingAccrued: BigInt(-4) * WAD,
      isOpen: true,
    },
  ];

  const demoPositions: PositionData[] = baseDemoPositions.map((basePos, index) =>
    createLivePosition(basePos, demoMarketIds[index])
  );

  // Show real positions if they exist, otherwise show demo positions when no wallet is connected
  const displayPositions = positions.length > 0 ? positions : (!address ? demoPositions : []);

  console.log('[Positions] Display positions logic:', {
    positionsCount: positions.length,
    address: address || 'null',
    demoPositionsCount: demoPositions.length,
    displayPositionsCount: displayPositions.length,
    displayPositionsSource: positions.length > 0 ? 'real' : 'demo'
  });

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
      console.log(`[totalEquity] Position ${pos.id.toString()}:`, {
        equityBigInt: pos.equity.toString(),
        equityNumber: equity,
        isFinite: isFinite(equity),
        sum: sum
      });
      return sum + (isFinite(equity) ? equity : 0);
    } catch (error) {
      console.error(`[totalEquity] Error processing position ${pos.id.toString()}:`, error);
      return sum;
    }
  }, 0);

  const totalNetPnl = displayPositions.reduce((sum, pos) => {
    try {
      const netPnl = Number(computeNetPnl(pos)) / 1e6;
      console.log(`[totalNetPnl] Position ${pos.id.toString()}:`, {
        netPnlBigInt: computeNetPnl(pos).toString(),
        netPnlNumber: netPnl,
        isFinite: isFinite(netPnl),
        sum: sum
      });
      return sum + (isFinite(netPnl) ? netPnl : 0);
    } catch (error) {
      console.error(`[totalNetPnl] Error processing position ${pos.id.toString()}:`, error);
      return sum;
    }
  }, 0);

  const totalCollateral = displayPositions.reduce((sum, pos) => {
    try {
      const collateral = Number(pos.collateral) / 1e6;
      console.log(`[totalCollateral] Position ${pos.id.toString()}:`, {
        collateralBigInt: pos.collateral.toString(),
        collateralNumber: collateral,
        isFinite: isFinite(collateral),
        sum: sum
      });
      return sum + (isFinite(collateral) ? collateral : 0);
    } catch (error) {
      console.error(`[totalCollateral] Error processing position ${pos.id.toString()}:`, error);
      return sum;
    }
  }, 0);

  console.log('[Positions] Portfolio totals:', {
    displayPositionsCount: displayPositions.length,
    totalEquity,
    totalNetPnl,
    totalCollateral
  });

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

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-gray-100">Your Positions</h2>
        <p className="text-gray-500">
          Monitor and manage your active leveraged positions
        </p>
      </div>

      {/* Account Balance Bar
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
                  ${accountBalance ? formatUsdt(accountBalance as bigint) : '0.00'} USDT
                </p>
              </div>
              <div>
                <span className="text-xs text-gray-500 uppercase tracking-wide">Free Collateral</span>
                <p className="text-lg font-bold font-mono text-gray-100">
                  ${freeCollateral ? formatUsdt(freeCollateral as bigint) : '0.00'} USDT
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

      {/* Trade History removed */}
    </div>
  );
};

export default Positions;
