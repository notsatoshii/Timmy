import React, { useState, useEffect } from 'react';
import { useReadContract } from 'wagmi';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import {
  OI_LIMITS_ABI,
  BORROW_FEE_ENGINE_ABI,
  FUNDING_RATE_ENGINE_ABI,
  ORACLE_ADAPTER_ABI,
  POSITION_MANAGER_ABI
} from '../config/abis';
import { useLivePrices } from '../hooks/useLivePrices';
import Skeleton from './Skeleton';

interface Market {
  id: string;
  description: string;
  price: number;
  resolutionTime: number;
  category: string;
  isLive: boolean;
}

interface MarketDetailProps {
  market: Market;
  onBack: () => void;
}

interface PositionData {
  id: string;
  trader: string;
  direction: 'long' | 'short';
  size: number;
  entryPrice: number;
  timestamp: number;
  pnl: number;
}

const MarketDetail: React.FC<MarketDetailProps> = ({ market, onBack }) => {
  const [priceHistory, setPriceHistory] = useState<{ time: number; price: number }[]>([]);
  const [recentPositions, setRecentPositions] = useState<PositionData[]>([]);

  // Helper function to convert market ID to bytes32 format
  const marketIdToBytes32 = (marketId: string): `0x${string}` => {
    // Convert demo market ID to bytes32
    // For demo purposes, we'll create a pseudo-hash from the ID
    const paddedId = marketId.padEnd(32, '0').slice(0, 32);
    const hex = Array.from(paddedId)
      .map(char => char.charCodeAt(0).toString(16).padStart(2, '0'))
      .join('')
      .slice(0, 64); // Ensure it's exactly 32 bytes (64 hex chars)
    return `0x${hex}` as `0x${string}`;
  };

  // Live price for this market
  const { prices: livePrices } = useLivePrices({
    marketIds: [market.id],
    pollingInterval: 30000,
    enabled: true,
  });

  // Convert market ID to bytes32 format for contract calls
  const marketBytes32 = marketIdToBytes32(market.id);

  // Get OI data
  const { data: longOI = 0 } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getSideOI',
    args: [marketBytes32, true], // true for long
  });

  const { data: shortOI = 0 } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getSideOI',
    args: [marketBytes32, false], // false for short
  });

  const { data: globalOI = 0 } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getGlobalOI',
  });

  // Get current rates (using long side for borrow rate)
  const { data: borrowRate = 0 } = useReadContract({
    address: CONTRACT_ADDRESSES.borrowFeeEngine,
    abi: BORROW_FEE_ENGINE_ABI,
    functionName: 'getCurrentBorrowRate',
    args: [marketBytes32, true], // true for long side
  });

  const { data: fundingRate = 0 } = useReadContract({
    address: CONTRACT_ADDRESSES.fundingRateEngine,
    abi: FUNDING_RATE_ENGINE_ABI,
    functionName: 'getCurrentFundingRate',
    args: [marketBytes32],
  });

  // Generate demo price history for chart
  useEffect(() => {
    const generatePriceHistory = () => {
      const history = [];
      const now = Date.now();
      const currentPrice = livePrices[market.id]?.pi || market.price;

      for (let i = 24; i >= 0; i--) {
        const timestamp = now - (i * 60 * 60 * 1000); // 24 hours ago to now
        const volatility = 0.02; // 2% volatility
        const randomChange = (Math.random() - 0.5) * volatility;
        const price = Math.max(0.01, Math.min(0.99, currentPrice + randomChange));
        history.push({ time: timestamp, price });
      }

      return history;
    };

    setPriceHistory(generatePriceHistory());
  }, [market.id, livePrices]);

  // Generate demo recent positions
  useEffect(() => {
    const generateRecentPositions = (): PositionData[] => {
      const positions = [];
      const now = Date.now();
      const currentPrice = livePrices[market.id]?.pi || market.price;

      for (let i = 0; i < 8; i++) {
        const direction: 'long' | 'short' = Math.random() > 0.5 ? 'long' : 'short';
        const entryPrice = currentPrice + (Math.random() - 0.5) * 0.1;
        const size = Math.random() * 50000 + 10000; // $10k - $60k
        const timestamp = now - (i * 15 * 60 * 1000); // Every 15 minutes
        const pnl = direction === 'long'
          ? (currentPrice - entryPrice) * size / entryPrice
          : (entryPrice - currentPrice) * size / entryPrice;

        positions.push({
          id: `pos-${i}`,
          trader: `0x${Math.random().toString(16).substr(2, 6)}...${Math.random().toString(16).substr(2, 4)}`,
          direction,
          size,
          entryPrice,
          timestamp,
          pnl,
        });
      }

      return positions;
    };

    setRecentPositions(generateRecentPositions());
  }, [market.id, livePrices]);

  const formatTimeToResolution = (timestamp: number): string => {
    const now = new Date().getTime();
    const diff = timestamp - now;

    if (diff < 0) return 'Expired';

    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));

    if (days > 0) return `${days}d ${hours}h`;
    return `${hours}h`;
  };

  const formatCurrency = (value: number): string => {
    if (value >= 1000000) return `$${(value / 1000000).toFixed(1)}M`;
    if (value >= 1000) return `$${(value / 1000).toFixed(1)}K`;
    return `$${value.toFixed(0)}`;
  };

  const formatRate = (rate: bigint): string => {
    const rateNum = Number(rate) / 1e18; // Convert from wei
    return `${(rateNum * 8760 * 100).toFixed(2)}%`; // Annual percentage
  };

  const formatTimestamp = (timestamp: number): string => {
    const now = Date.now();
    const diff = Math.floor((now - timestamp) / 1000);

    if (diff < 60) return 'Just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    return `${Math.floor(diff / 86400)}d ago`;
  };

  const getCategoryColor = (category: string): string => {
    const colors: { [key: string]: string } = {
      'Politics': 'bg-purple-muted text-purple border border-purple/20',
      'Sports': 'bg-accent-muted text-accent border border-accent/20',
      'Technology': 'bg-purple-muted text-purple border border-purple/20',
      'Economy': 'bg-warning-muted text-warning border border-warning/20',
      'Crypto': 'bg-warning-muted text-warning border border-warning/20',
      'Entertainment': 'bg-purple-muted text-purple border border-purple/20',
      'Other': 'bg-surface-3 text-gray-400 border border-border',
      'Geopolitics': 'bg-danger-muted text-danger border border-danger/20',
      'Speculative': 'bg-purple-muted text-purple border border-purple/20',
      'Stocks': 'bg-accent-muted text-accent border border-accent/20',
      'Forex': 'bg-accent-muted text-accent border border-accent/20',
    };
    return colors[category] || colors['Other'];
  };

  const currentPrice = livePrices[market.id]?.pi || market.price;
  const totalOI = Number(longOI || 0) + Number(shortOI || 0);
  const longPercentage = totalOI > 0 ? (Number(longOI || 0) / totalOI) * 100 : 50;
  const shortPercentage = 100 - longPercentage;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <button
          onClick={onBack}
          className="flex items-center space-x-2 text-gray-400 hover:text-gray-200 transition-colors"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          <span>Back to Markets</span>
        </button>
      </div>

      {/* Market Header */}
      <div className="bg-surface-1 rounded-lg border border-border p-6">
        <div className="flex flex-col space-y-4 lg:flex-row lg:items-start lg:justify-between lg:space-y-0">
          <div className="flex-1">
            <div className="flex items-center space-x-3 mb-4">
              <span
                className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getCategoryColor(market.category)}`}
              >
                {market.category}
              </span>
              {market.isLive && (
                <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-accent-muted text-accent border border-accent/20">
                  <div className="w-1.5 h-1.5 bg-accent rounded-full mr-1 animate-pulse"></div>
                  Live
                </span>
              )}
            </div>

            <h1 className="text-2xl font-bold text-gray-100 mb-4">
              {market.description}
            </h1>

            <div className="grid grid-cols-2 gap-6 sm:grid-cols-4">
              <div>
                <p className="text-gray-500 text-sm">Current Price</p>
                <p className="text-2xl font-bold text-accent font-mono">
                  {(currentPrice * 100).toFixed(1)}¢
                </p>
              </div>
              <div>
                <p className="text-gray-500 text-sm">Probability</p>
                <p className="text-2xl font-bold text-gray-100 font-mono">
                  {(currentPrice * 100).toFixed(1)}%
                </p>
              </div>
              <div>
                <p className="text-gray-500 text-sm">Resolution</p>
                <p className="text-lg font-semibold text-gray-200">
                  {formatTimeToResolution(market.resolutionTime)}
                </p>
              </div>
              <div>
                <p className="text-gray-500 text-sm">Total OI</p>
                <p className="text-lg font-semibold text-gray-200">
                  {formatCurrency(totalOI)}
                </p>
              </div>
            </div>
          </div>

          <div className="flex-shrink-0 lg:ml-6">
            <div className="flex space-x-3">
              <button className="bg-accent/10 text-accent border border-accent/30 px-6 py-3 rounded-md font-semibold hover:bg-accent/20 hover:border-accent/50 transition-all">
                Long
              </button>
              <button className="bg-danger/10 text-danger border border-danger/30 px-6 py-3 rounded-md font-semibold hover:bg-danger/20 hover:border-danger/50 transition-all">
                Short
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Charts and Stats Grid */}
      <div className="grid gap-6 lg:grid-cols-2">
        {/* Price Chart */}
        <div className="bg-surface-1 rounded-lg border border-border p-6">
          <h3 className="text-lg font-semibold text-gray-100 mb-4">
            24H Price Chart
          </h3>
          <div className="h-48 flex items-end justify-between space-x-1">
            {priceHistory.map((point, index) => {
              const height = (point.price * 100) + '%';
              const isRecent = index >= priceHistory.length - 3;
              return (
                <div
                  key={index}
                  className={`flex-1 rounded-sm transition-all duration-300 ${
                    isRecent ? 'bg-accent' : 'bg-gray-600'
                  }`}
                  style={{ height }}
                ></div>
              );
            })}
          </div>
          <div className="flex justify-between text-xs text-gray-500 mt-2">
            <span>24h ago</span>
            <span>Now</span>
          </div>
        </div>

        {/* OI Breakdown */}
        <div className="bg-surface-1 rounded-lg border border-border p-6">
          <h3 className="text-lg font-semibold text-gray-100 mb-4">
            Open Interest Breakdown
          </h3>

          <div className="space-y-4">
            {/* Visual OI Bar */}
            <div className="flex h-8 rounded-md overflow-hidden">
              <div
                className="bg-accent flex items-center justify-center text-xs font-medium text-surface-0"
                style={{ width: `${longPercentage}%` }}
              >
                Long {longPercentage.toFixed(0)}%
              </div>
              <div
                className="bg-danger flex items-center justify-center text-xs font-medium text-surface-0"
                style={{ width: `${shortPercentage}%` }}
              >
                Short {shortPercentage.toFixed(0)}%
              </div>
            </div>

            {/* OI Details */}
            <div className="grid grid-cols-2 gap-4">
              <div className="text-center">
                <p className="text-accent text-2xl font-bold font-mono">
                  {formatCurrency(Number(longOI || 0))}
                </p>
                <p className="text-sm text-gray-500">Long OI</p>
              </div>
              <div className="text-center">
                <p className="text-danger text-2xl font-bold font-mono">
                  {formatCurrency(Number(shortOI || 0))}
                </p>
                <p className="text-sm text-gray-500">Short OI</p>
              </div>
            </div>
          </div>
        </div>

        {/* Rates */}
        <div className="bg-surface-1 rounded-lg border border-border p-6">
          <h3 className="text-lg font-semibold text-gray-100 mb-4">
            Current Rates
          </h3>

          <div className="grid grid-cols-2 gap-6">
            <div>
              <p className="text-gray-500 text-sm mb-1">Funding Rate</p>
              <p className="text-xl font-bold text-purple font-mono">
                {formatRate(BigInt(fundingRate || 0))}
              </p>
              <p className="text-xs text-gray-600">Annual</p>
            </div>
            <div>
              <p className="text-gray-500 text-sm mb-1">Borrow Rate</p>
              <p className="text-xl font-bold text-warning font-mono">
                {formatRate(BigInt(borrowRate || 0))}
              </p>
              <p className="text-xs text-gray-600">Annual</p>
            </div>
          </div>

          <div className="mt-4 pt-4 border-t border-border">
            <p className="text-xs text-gray-600">
              Funding rate: Heavy side pays light side.
              Borrow rate: Cost for leveraged positions.
            </p>
          </div>
        </div>

        {/* Recent Positions */}
        <div className="bg-surface-1 rounded-lg border border-border p-6">
          <h3 className="text-lg font-semibold text-gray-100 mb-4">
            Recent Positions
          </h3>

          <div className="space-y-3">
            {recentPositions.slice(0, 5).map((position) => (
              <div key={position.id} className="flex items-center justify-between py-2">
                <div className="flex items-center space-x-3">
                  <span
                    className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium ${
                      position.direction === 'long'
                        ? 'bg-accent/10 text-accent'
                        : 'bg-danger/10 text-danger'
                    }`}
                  >
                    {position.direction.toUpperCase()}
                  </span>
                  <div>
                    <p className="text-sm text-gray-200 font-mono">
                      {formatCurrency(position.size)}
                    </p>
                    <p className="text-xs text-gray-500">
                      {position.trader}
                    </p>
                  </div>
                </div>

                <div className="text-right">
                  <p className={`text-sm font-medium font-mono ${
                    position.pnl >= 0 ? 'text-accent' : 'text-danger'
                  }`}>
                    {position.pnl >= 0 ? '+' : ''}
                    {formatCurrency(position.pnl)}
                  </p>
                  <p className="text-xs text-gray-500">
                    {formatTimestamp(position.timestamp)}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

export default MarketDetail;