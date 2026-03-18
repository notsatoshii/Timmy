import React, { useState, useEffect } from 'react';
import { useReadContract } from 'wagmi';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import {
  OI_LIMITS_ABI,
  BORROW_FEE_ENGINE_ABI,
  FUNDING_RATE_ENGINE_ABI
} from '../config/abis';
import { useMarketProbabilities } from '../hooks/useMarketProbabilities';
import {
  ComposedChart,
  Bar,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer
} from 'recharts';

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
  onTradeSelect?: (marketId: string, marketName: string, direction: 'long' | 'short') => void;
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

interface CandlestickData {
  time: number;
  timestamp: string;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

type TimeFrame = '1m' | '5m' | '15m' | '1h' | '4h' | '1D';

const MarketDetail: React.FC<MarketDetailProps> = ({ market, onBack, onTradeSelect }) => {
  const [candlestickData, setCandlestickData] = useState<CandlestickData[]>([]);
  const [selectedTimeframe, setSelectedTimeframe] = useState<TimeFrame>('1h');
  const [recentPositions, setRecentPositions] = useState<PositionData[]>([]);

  // Get real-time price from the same source as Markets component
  const {
    markets: oracleMarkets,
    hasOracleData,
    refreshProbabilities
  } = useMarketProbabilities({
    pollingInterval: 30000,
    enabled: true,
  });

  // Find current market in oracle data
  const currentMarketData = oracleMarkets.find(m => m.id === market.id);
  const currentPrice = currentMarketData ? currentMarketData.probability : market.price;

  // Convert market ID to bytes32 format for contract calls (already in correct format)
  const marketBytes32 = market.id as `0x${string}`;

  // Get OI data with error handling
  const { data: longOI = 0, error: longOIError, isLoading: longOILoading } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getSideOI',
    args: [marketBytes32, true], // true for long
    query: {
      enabled: !!market.id && !!CONTRACT_ADDRESSES.oiLimits,
    },
  });

  const { data: shortOI = 0, error: shortOIError, isLoading: shortOILoading } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getSideOI',
    args: [marketBytes32, false], // false for short
    query: {
      enabled: !!market.id && !!CONTRACT_ADDRESSES.oiLimits,
    },
  });

  // Get current rates (using long side for borrow rate)
  const { data: borrowRate = 0, error: borrowRateError, isLoading: borrowRateLoading } = useReadContract({
    address: CONTRACT_ADDRESSES.borrowFeeEngine,
    abi: BORROW_FEE_ENGINE_ABI,
    functionName: 'getCurrentBorrowRate',
    args: [marketBytes32, true], // true for long side
    query: {
      enabled: !!market.id && !!CONTRACT_ADDRESSES.borrowFeeEngine,
    },
  });

  const { data: fundingRate = 0, error: fundingRateError, isLoading: fundingRateLoading } = useReadContract({
    address: CONTRACT_ADDRESSES.fundingRateEngine,
    abi: FUNDING_RATE_ENGINE_ABI,
    functionName: 'getCurrentFundingRate',
    args: [marketBytes32],
    query: {
      enabled: !!market.id && !!CONTRACT_ADDRESSES.fundingRateEngine,
    },
  });

  // Generate demo candlestick data for chart
  useEffect(() => {
    const generateCandlestickData = (): CandlestickData[] => {
      const data: CandlestickData[] = [];
      const now = Date.now();

      // Timeframe intervals in milliseconds
      const intervals: Record<TimeFrame, number> = {
        '1m': 60 * 1000,
        '5m': 5 * 60 * 1000,
        '15m': 15 * 60 * 1000,
        '1h': 60 * 60 * 1000,
        '4h': 4 * 60 * 60 * 1000,
        '1D': 24 * 60 * 60 * 1000,
      };

      // Number of candles to generate
      const candleCount: Record<TimeFrame, number> = {
        '1m': 60, // Last hour
        '5m': 72, // Last 6 hours
        '15m': 96, // Last 24 hours
        '1h': 168, // Last week
        '4h': 168, // Last 4 weeks
        '1D': 30, // Last month
      };

      const interval = intervals[selectedTimeframe];
      const count = candleCount[selectedTimeframe];
      const volatility = 0.015; // 1.5% volatility per candle

      // Ensure currentPrice is valid, fallback to market.price or 0.5
      let price = currentPrice;
      if (typeof price !== 'number' || isNaN(price) || price <= 0) {
        price = typeof market.price === 'number' && !isNaN(market.price) ? market.price : 0.5;
      }

      for (let i = count; i >= 0; i--) {
        const timestamp = now - (i * interval);

        // Generate OHLC data
        const open = price;
        const randomMove = (Math.random() - 0.5) * volatility;
        const close = Math.max(0.01, Math.min(0.99, open + randomMove));

        // High and low based on open/close with some randomness
        const range = Math.abs(close - open);
        const maxRange = Math.max(range * 1.5, volatility * 0.5);
        const high = Math.min(0.99, Math.max(open, close) + Math.random() * maxRange);
        const low = Math.max(0.01, Math.min(open, close) - Math.random() * maxRange);

        // Volume simulation
        const volume = Math.random() * 100000 + 10000;

        // Format timestamp for display
        const timestampStr = selectedTimeframe === '1D'
          ? new Date(timestamp).toLocaleDateString()
          : new Date(timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

        data.push({
          time: timestamp,
          timestamp: timestampStr,
          open,
          high,
          low,
          close,
          volume,
        });

        price = close; // Next candle starts where this one ended
      }

      return data;
    };

    setCandlestickData(generateCandlestickData());
  }, [market.id, market.price, currentPrice, selectedTimeframe]);

  // Generate demo recent positions
  useEffect(() => {
    const generateRecentPositions = (): PositionData[] => {
      const positions = [];
      const now = Date.now();

      // Ensure currentPrice is valid
      const validCurrentPrice = typeof currentPrice === 'number' && !isNaN(currentPrice) && currentPrice > 0
        ? currentPrice
        : (typeof market.price === 'number' && !isNaN(market.price) ? market.price : 0.5);

      for (let i = 0; i < 8; i++) {
        const direction: 'long' | 'short' = Math.random() > 0.5 ? 'long' : 'short';
        const entryPrice = validCurrentPrice + (Math.random() - 0.5) * 0.1;
        const size = Math.random() * 50000 + 10000; // $10k - $60k
        const timestamp = now - (i * 15 * 60 * 1000); // Every 15 minutes

        // Safe PnL calculation with zero division check
        let pnl = 0;
        if (entryPrice > 0) {
          pnl = direction === 'long'
            ? (validCurrentPrice - entryPrice) * size / entryPrice
            : (entryPrice - validCurrentPrice) * size / entryPrice;
        }

        // Ensure PnL is not NaN
        if (isNaN(pnl)) pnl = 0;

        positions.push({
          id: `pos-${i}`,
          trader: `0x${Math.random().toString(16).substring(2, 8)}...${Math.random().toString(16).substring(2, 6)}`,
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
  }, [market.id, market.price, currentPrice]);

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

  const formatRate = (rate: bigint | number | undefined): string => {
    try {
      let rateBigInt: bigint;
      if (typeof rate === 'bigint') {
        rateBigInt = rate;
      } else if (typeof rate === 'number' && !isNaN(rate) && isFinite(rate)) {
        rateBigInt = BigInt(Math.floor(rate));
      } else {
        return '0.00%';
      }
      const rateNum = Number(rateBigInt) / 1e18; // Convert from wei
      if (isNaN(rateNum) || !isFinite(rateNum)) return '0.00%';
      const hourlyRate = rateNum * 100; // Hourly percentage
      if (isNaN(hourlyRate) || !isFinite(hourlyRate)) return '0.0000%';
      return `${hourlyRate.toFixed(4)}%`;
    } catch (error) {
      console.warn('Error formatting rate:', rate, error);
      return '0.00%';
    }
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

  // Timeframe configurations
  const timeframes: { value: TimeFrame; label: string }[] = [
    { value: '1m', label: '1M' },
    { value: '5m', label: '5M' },
    { value: '15m', label: '15M' },
    { value: '1h', label: '1H' },
    { value: '4h', label: '4H' },
    { value: '1D', label: '1D' },
  ];

  // Custom candlestick renderer
  const CandlestickBar = (props: any) => {
    const { payload, x, y, width, height } = props;
    if (!payload) return null;

    const { open, high, low, close } = payload;
    const isGreen = close >= open;
    const color = isGreen ? '#00E8B4' : '#FF4868'; // accent vs danger colors

    // Calculate candle body
    const bodyTop = Math.min(open, close) * height;
    const bodyHeight = Math.abs(close - open) * height;

    // Calculate wick positions
    const highY = high * height;
    const lowY = low * height;
    const wickX = x + width / 2;

    return (
      <g>
        {/* High-Low Wick */}
        <line
          x1={wickX}
          y1={y + height - highY}
          x2={wickX}
          y2={y + height - lowY}
          stroke={color}
          strokeWidth={1}
        />
        {/* Candle Body */}
        <rect
          x={x + width * 0.2}
          y={y + height - bodyTop - bodyHeight}
          width={width * 0.6}
          height={Math.max(bodyHeight, 1)}
          fill={isGreen ? color : 'transparent'}
          stroke={color}
          strokeWidth={isGreen ? 0 : 1}
        />
      </g>
    );
  };

  // Custom tooltip
  const CustomTooltip = ({ active, payload, label }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      const isGreen = data.close >= data.open;

      return (
        <div className="bg-surface-1 border border-border rounded-lg p-3 shadow-lg">
          <p className="text-gray-400 text-xs mb-2">{data.timestamp}</p>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <div>
              <span className="text-gray-500">O: </span>
              <span className="text-gray-200 font-mono">{(data.open * 100).toFixed(1)}¢</span>
            </div>
            <div>
              <span className="text-gray-500">H: </span>
              <span className="text-gray-200 font-mono">{(data.high * 100).toFixed(1)}¢</span>
            </div>
            <div>
              <span className="text-gray-500">L: </span>
              <span className="text-gray-200 font-mono">{(data.low * 100).toFixed(1)}¢</span>
            </div>
            <div>
              <span className="text-gray-500">C: </span>
              <span className={`font-mono ${isGreen ? 'text-accent' : 'text-danger'}`}>
                {(data.close * 100).toFixed(1)}¢
              </span>
            </div>
          </div>
        </div>
      );
    }
    return null;
  };

  // Safe BigInt to Number conversion for OI values (USDT format - 6 decimals, divide by 1e6)
  const longOINum = (() => {
    try {
      if (typeof longOI === 'bigint') {
        const num = Number(longOI) / 1e6;
        return isFinite(num) ? num : 0;
      } else if (typeof longOI === 'number' && !isNaN(longOI) && isFinite(longOI)) {
        return longOI / 1e6;
      }
      return 0;
    } catch (error) {
      console.warn('Error converting longOI:', longOI, error);
      return 0;
    }
  })();

  const shortOINum = (() => {
    try {
      if (typeof shortOI === 'bigint') {
        const num = Number(shortOI) / 1e6;
        return isFinite(num) ? num : 0;
      } else if (typeof shortOI === 'number' && !isNaN(shortOI) && isFinite(shortOI)) {
        return shortOI / 1e6;
      }
      return 0;
    } catch (error) {
      console.warn('Error converting shortOI:', shortOI, error);
      return 0;
    }
  })();

  // Log contract call errors for debugging
  useEffect(() => {
    if (longOIError) console.error('Long OI contract call error:', longOIError);
    if (shortOIError) console.error('Short OI contract call error:', shortOIError);
    if (borrowRateError) console.error('Borrow rate contract call error:', borrowRateError);
    if (fundingRateError) console.error('Funding rate contract call error:', fundingRateError);
  }, [longOIError, shortOIError, borrowRateError, fundingRateError]);

  const totalOI = longOINum + shortOINum;
  const longPercentage = totalOI > 0 ? (longOINum / totalOI) * 100 : 50;
  const shortPercentage = totalOI > 0 ? (shortOINum / totalOI) * 100 : 50;

  // Validate market data after all hooks are called
  if (!market) {
    return (
      <div className="bg-surface-1 border border-danger/30 rounded-lg p-8 text-center">
        <div className="text-danger mb-4">
          <h3 className="text-lg font-semibold">Invalid Market Data</h3>
          <p className="text-sm text-gray-400">Market data is missing or invalid.</p>
        </div>
        <button
          onClick={onBack}
          className="px-4 py-2 bg-accent text-surface-0 rounded-md hover:bg-accent-dim transition-colors"
        >
          Back to Markets
        </button>
      </div>
    );
  }

  if (!market.id || typeof market.price !== 'number' || isNaN(market.price)) {
    console.error('Invalid market data:', market);
    return (
      <div className="bg-surface-1 border border-danger/30 rounded-lg p-8 text-center">
        <div className="text-danger mb-4">
          <h3 className="text-lg font-semibold">Invalid Market Data</h3>
          <p className="text-sm text-gray-400">Market ID or price data is invalid.</p>
          <p className="text-xs text-gray-500 mt-2 font-mono">
            ID: {market?.id || 'missing'}, Price: {typeof market?.price === 'number' ? market.price : 'invalid'}
          </p>
        </div>
        <button
          onClick={onBack}
          className="px-4 py-2 bg-accent text-surface-0 rounded-md hover:bg-accent-dim transition-colors"
        >
          Back to Markets
        </button>
      </div>
    );
  }

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

        <button
          onClick={refreshProbabilities}
          className="text-sm text-gray-500 hover:text-gray-300 px-3 py-1 rounded border border-border hover:border-border-light transition-colors"
        >
          Refresh Price
        </button>
      </div>

      {/* Market Header */}
      <div className="bg-surface-1 rounded-lg border border-border p-6">
        <div className="flex flex-col space-y-4 lg:flex-row lg:items-start lg:justify-between lg:space-y-0">
          <div className="flex-1">
            <div className="flex items-center space-x-3 mb-4">
              <span
                className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getCategoryColor(market?.category || '')}`}
              >
                {market?.category || 'Unknown'}
              </span>
              {market?.isLive && (
                <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-accent-muted text-accent border border-accent/20">
                  <div className="w-1.5 h-1.5 bg-accent rounded-full mr-1 animate-pulse"></div>
                  Live
                </span>
              )}
            </div>

            <h1 className="text-2xl font-bold text-gray-100 mb-4">
              {market?.description || 'Unknown Market'}
            </h1>

            <div className="grid grid-cols-2 gap-6 sm:grid-cols-4">
              <div>
                <p className="text-gray-500 text-sm flex items-center">
                  Current Price
                  <span className={`ml-2 w-2 h-2 rounded-full animate-pulse ${
                    hasOracleData ? 'bg-accent' : 'bg-warning'
                  }`}></span>
                </p>
                <p className="text-2xl font-bold text-accent font-mono">
                  {(currentPrice * 100).toFixed(1)}¢
                </p>
                <p className="text-xs text-gray-600">
                  {hasOracleData ? 'Live Oracle' : 'Demo Fallback'}
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
                  {formatTimeToResolution(market?.resolutionTime || Date.now())}
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
              <button onClick={() => { if (onTradeSelect && market?.id) onTradeSelect(market.id, market.description || 'Unknown', "long"); if (onBack) onBack(); }} className="bg-accent/10 text-accent border border-accent/30 px-6 py-3 rounded-md font-semibold hover:bg-accent/20 hover:border-accent/50 transition-all">
                Long
              </button>
              <button onClick={() => { if (onTradeSelect && market?.id) onTradeSelect(market.id, market.description || 'Unknown', "short"); if (onBack) onBack(); }} className="bg-danger/10 text-danger border border-danger/30 px-6 py-3 rounded-md font-semibold hover:bg-danger/20 hover:border-danger/50 transition-all">
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
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-100">
              Price Chart
            </h3>

            {/* Timeframe Selector */}
            <div className="flex space-x-1 bg-surface-2 rounded-md p-1">
              {timeframes.map((timeframe) => (
                <button
                  key={timeframe.value}
                  onClick={() => setSelectedTimeframe(timeframe.value)}
                  className={`px-3 py-1 text-xs font-medium rounded transition-all ${
                    selectedTimeframe === timeframe.value
                      ? 'bg-accent text-surface-0'
                      : 'text-gray-400 hover:text-gray-200 hover:bg-surface-3'
                  }`}
                >
                  {timeframe.label}
                </button>
              ))}
            </div>
          </div>

          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <ComposedChart
                data={candlestickData}
                margin={{ top: 20, right: 30, left: 20, bottom: 20 }}
              >
                <CartesianGrid
                  strokeDasharray="3 3"
                  stroke="#374151"
                  opacity={0.3}
                />
                <XAxis
                  dataKey="timestamp"
                  axisLine={false}
                  tickLine={false}
                  tick={{ fontSize: 10, fill: '#9CA3AF' }}
                  interval="preserveStartEnd"
                />
                <YAxis
                  domain={['dataMin - 0.01', 'dataMax + 0.01']}
                  tickFormatter={(value) => `${(value * 100).toFixed(0)}¢`}
                  axisLine={false}
                  tickLine={false}
                  tick={{ fontSize: 10, fill: '#9CA3AF' }}
                  width={40}
                />
                <Tooltip content={<CustomTooltip />} />
                <Bar
                  dataKey={(entry: CandlestickData) => [entry.low, entry.high]}
                  shape={<CandlestickBar />}
                />
                <Line
                  type="monotone"
                  dataKey="close"
                  stroke="transparent"
                  dot={false}
                  strokeWidth={0}
                />
              </ComposedChart>
            </ResponsiveContainer>
          </div>

          <div className="flex justify-between items-center text-xs text-gray-500 mt-2">
            <span>
              {selectedTimeframe === '1D' ? 'Last 30 days' :
               selectedTimeframe === '4h' ? 'Last 4 weeks' :
               selectedTimeframe === '1h' ? 'Last week' :
               selectedTimeframe === '15m' ? 'Last 24 hours' :
               selectedTimeframe === '5m' ? 'Last 6 hours' :
               'Last hour'}
            </span>
            <span className="text-accent">
              Current: {(currentPrice * 100).toFixed(1)}¢
            </span>
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
                  {formatCurrency(longOINum)}
                </p>
                <p className="text-sm text-gray-500">Long OI</p>
              </div>
              <div className="text-center">
                <p className="text-danger text-2xl font-bold font-mono">
                  {formatCurrency(shortOINum)}
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
                {formatRate(fundingRate)}
              </p>
              <p className="text-xs text-gray-600">Per Hour</p>
            </div>
            <div>
              <p className="text-gray-500 text-sm mb-1">Borrow Rate</p>
              <p className="text-xl font-bold text-warning font-mono">
                {formatRate(borrowRate)}
              </p>
              <p className="text-xs text-gray-600">Per Hour</p>
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