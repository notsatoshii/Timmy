import React, { useState, useEffect } from 'react';
import { useReadContract, usePublicClient } from 'wagmi';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import {
  OI_LIMITS_ABI,
  BORROW_FEE_ENGINE_ABI,
  FUNDING_RATE_ENGINE_ABI,
  ORACLE_ADAPTER_ABI,
  EXECUTION_ENGINE_ABI
} from '../config/abis';
import { useMarketProbabilities } from '../hooks/useMarketProbabilities';
import TradeForm from './TradeForm';
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

// Map demo market IDs to on-chain bytes32 market IDs for contract calls
const DEMO_TO_ONCHAIN_ID: Record<string, string> = {
  'demo-1': '0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1',
  'demo-2': '0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a',
  'demo-3': '0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d',
  'demo-4': '0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2',
  'demo-5': '0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7',
  'demo-6': '0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2',
  'demo-7': '0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554',
  'demo-8': '0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc',
  'demo-9': '0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f',
  'demo-10': '0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea',
  'demo-11': '0x8215cf9d075f1ee6044f05d17fa1685d88da515f3ea119e10f50cb487f9e3774',
  'demo-12': '0x329ec977deb23dbc392959044918040f8a9252d502c6948eea33d2e72e787ddd',
  'demo-13': '0xc2a3fba66cdee6088484ae353b3c414390c591ac5cf485248f9b9cbb591a8cd4',
  'demo-14': '0x35f95cb4e4331813cbbcf8acd4efea29305a24ff890b4f22d163722095ebb706',
  'demo-15': '0x73b37115e0a747b8fec07143017b8359a53677baa466a4847c6af7c14c0ec5c7',
  'demo-16': '0x6ee69274ed792087cd80dc1db0f90456f4d2621287375a0e90032f61bbe32e9e',
  'demo-17': '0xdf341f72d47f0bbcb009aaa13d9d683a79ce8f77de068943c0316feade190c21',
  'demo-18': '0x0e6da084b18fb861b29203d611dc83df2bcfa3294281dd57ea735f3096023438',
  'demo-19': '0x5131ef671dbddffe63e34798f3cf92be05c95001b20f29255f97d87b2d6e1de2',
  'demo-20': '0x7155116cef46226d9a58e096c87fba03555313c85b9b9b649dca754090845136',
};

const CATEGORY_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  Technology: { bg: 'bg-purple-muted', text: 'text-purple', border: 'border-purple/20' },
  Geopolitics: { bg: 'bg-danger-muted', text: 'text-danger', border: 'border-danger/20' },
  Economy: { bg: 'bg-warning-muted', text: 'text-warning', border: 'border-warning/20' },
  Sports: { bg: 'bg-accent-muted', text: 'text-accent', border: 'border-accent/20' },
  Crypto: { bg: 'bg-warning-muted', text: 'text-warning', border: 'border-warning/20' },
  Stocks: { bg: 'bg-accent-muted', text: 'text-accent', border: 'border-accent/20' },
  Forex: { bg: 'bg-accent-muted', text: 'text-accent', border: 'border-accent/20' },
  Politics: { bg: 'bg-purple-muted', text: 'text-purple', border: 'border-purple/20' },
  Speculative: { bg: 'bg-purple-muted', text: 'text-purple', border: 'border-purple/20' },
  Entertainment: { bg: 'bg-purple-muted', text: 'text-purple', border: 'border-purple/20' },
};

interface RecentTrade {
  positionId: string;
  owner: string;
  isLong: boolean;
  collateral: bigint;
  leverage: bigint;
  positionSize: bigint;
  entryPrice: bigint;
  timestamp: bigint;
  txHash: string;
  blockNumber: bigint;
}

const MarketDetail: React.FC<MarketDetailProps> = ({ market, onBack, onTradeSelect }) => {
  const [candlestickData, setCandlestickData] = useState<CandlestickData[]>([]);
  const [selectedTimeframe, setSelectedTimeframe] = useState<TimeFrame>('1h');
  const [recentTrades, setRecentTrades] = useState<RecentTrade[]>([]);
  const [tradesLoading, setTradesLoading] = useState(false);
  const publicClient = usePublicClient();

  const { markets: oracleMarkets, hasOracleData, refreshProbabilities } = useMarketProbabilities({ pollingInterval: 30000, enabled: true });
  const currentMarketData = oracleMarkets.find(m => m.id === market.id);
  const currentPrice = currentMarketData ? currentMarketData.probability : market.price;

  const marketBytes32 = React.useMemo(() => {
    if (!market?.id) return '0x0000000000000000000000000000000000000000000000000000000000000000' as `0x${string}`;
    const onchainId = DEMO_TO_ONCHAIN_ID[market.id] || market.id;
    return onchainId as `0x${string}`;
  }, [market?.id]);

  const validMarketId = marketBytes32 !== '0x0000000000000000000000000000000000000000000000000000000000000000';

  // Contract reads
  const { data: longOI = BigInt(0) } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits, abi: OI_LIMITS_ABI, functionName: 'getSideOI',
    args: [marketBytes32, true], query: { enabled: validMarketId },
  });
  const { data: shortOI = BigInt(0) } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits, abi: OI_LIMITS_ABI, functionName: 'getSideOI',
    args: [marketBytes32, false], query: { enabled: validMarketId },
  });
  const { data: marketOICap = BigInt(0) } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits, abi: OI_LIMITS_ABI, functionName: 'getMarketOICap',
    args: [marketBytes32], query: { enabled: validMarketId },
  });
  const { data: globalOICap = BigInt(0) } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits, abi: OI_LIMITS_ABI, functionName: 'getGlobalOICap',
    query: { enabled: validMarketId },
  });
  const { data: globalOI = BigInt(0) } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits, abi: OI_LIMITS_ABI, functionName: 'getGlobalOI',
    query: { enabled: validMarketId },
  });
  const { data: sideOICap = BigInt(0) } = useReadContract({
    address: CONTRACT_ADDRESSES.oiLimits, abi: OI_LIMITS_ABI, functionName: 'getSideOICap',
    args: [marketBytes32], query: { enabled: validMarketId },
  });
  const { data: onChainPI } = useReadContract({
    address: CONTRACT_ADDRESSES.oracleAdapter, abi: ORACLE_ADAPTER_ABI, functionName: 'getPI',
    args: [marketBytes32], query: { enabled: validMarketId },
  });
  const { data: borrowRate = BigInt(0) } = useReadContract({
    address: CONTRACT_ADDRESSES.borrowFeeEngine, abi: BORROW_FEE_ENGINE_ABI, functionName: 'getCurrentBorrowRate',
    args: [marketBytes32, true], query: { enabled: validMarketId },
  });
  const { data: fundingRate = BigInt(0) } = useReadContract({
    address: CONTRACT_ADDRESSES.fundingRateEngine, abi: FUNDING_RATE_ENGINE_ABI, functionName: 'getCurrentFundingRate',
    args: [marketBytes32], query: { enabled: validMarketId },
  });

  const mtmPrice = onChainPI ? Number(onChainPI) / 1e18 : null;

  // Fetch recent PositionOpened events for this market
  useEffect(() => {
    if (!publicClient || !validMarketId || !CONTRACT_ADDRESSES.executionEngine) return;

    const fetchTrades = async () => {
      setTradesLoading(true);
      try {
        const currentBlock = await publicClient.getBlockNumber();
        // Look back ~50k blocks (~2 days on Base Sepolia)
        const fromBlock = currentBlock > 50000n ? currentBlock - 50000n : 0n;

        const logs = await publicClient.getLogs({
          address: CONTRACT_ADDRESSES.executionEngine as `0x${string}`,
          event: {
            type: 'event',
            name: 'PositionOpened',
            inputs: [
              { name: 'positionId', type: 'uint256', indexed: true },
              { name: 'marketId', type: 'bytes32', indexed: true },
              { name: 'owner', type: 'address', indexed: true },
              { name: 'isLong', type: 'bool', indexed: false },
              { name: 'collateral', type: 'uint256', indexed: false },
              { name: 'leverage', type: 'uint256', indexed: false },
              { name: 'entryPI', type: 'uint256', indexed: false },
              { name: 'entryPrice', type: 'uint256', indexed: false },
              { name: 'positionSize', type: 'uint256', indexed: false },
              { name: 'impact', type: 'uint256', indexed: false },
              { name: 'timestamp', type: 'uint256', indexed: false },
            ],
          },
          args: { marketId: marketBytes32 },
          fromBlock,
          toBlock: currentBlock,
        });

        const trades: RecentTrade[] = logs
          .filter(log => log.args && log.transactionHash)
          .map(log => ({
            positionId: (log.args.positionId as bigint).toString(),
            owner: log.args.owner as string,
            isLong: log.args.isLong as boolean,
            collateral: log.args.collateral as bigint,
            leverage: log.args.leverage as bigint,
            positionSize: log.args.positionSize as bigint,
            entryPrice: log.args.entryPrice as bigint,
            timestamp: log.args.timestamp as bigint,
            txHash: log.transactionHash!,
            blockNumber: log.blockNumber,
          }))
          .sort((a, b) => Number(b.timestamp - a.timestamp))
          .slice(0, 10); // Show last 10 trades

        setRecentTrades(trades);
      } catch (err) {
        console.warn('Failed to fetch recent trades:', err);
        setRecentTrades([]);
      } finally {
        setTradesLoading(false);
      }
    };

    fetchTrades();
  }, [publicClient, marketBytes32, validMarketId]);

  // OI numbers
  const toNum = (v: unknown): number => {
    if (typeof v === 'bigint') return Number(v) / 1e6;
    if (typeof v === 'number' && isFinite(v)) return v / 1e6;
    return 0;
  };
  const longOINum = toNum(longOI);
  const shortOINum = toNum(shortOI);
  const totalOI = longOINum + shortOINum;
  const marketCapNum = toNum(marketOICap);
  const globalCapNum = toNum(globalOICap);
  const globalOINum = toNum(globalOI);
  const sideCapNum = toNum(sideOICap);
  const longPct = totalOI > 0 ? (longOINum / totalOI) * 100 : 50;
  const shortPct = totalOI > 0 ? (shortOINum / totalOI) * 100 : 50;
  const depthUsedPct = marketCapNum > 0 ? Math.min((totalOI / marketCapNum) * 100, 100) : 0;
  const depthAvailable = marketCapNum > 0 ? marketCapNum - totalOI : 0;

  // Tier utilizations for depth viz (all as % of market cap for relative positioning)
  const globalUsedPct = globalCapNum > 0 ? Math.min((globalOINum / globalCapNum) * 100, 100) : 0;
  const sideCapPct = marketCapNum > 0 ? Math.min((sideCapNum / marketCapNum) * 100, 100) : 0;
  const heavySideOI = Math.max(longOINum, shortOINum);
  const heavySidePct = sideCapNum > 0 ? Math.min((heavySideOI / sideCapNum) * 100, 100) : 0;

  const formatRate = (rate: unknown): string => {
    try {
      const r = typeof rate === 'bigint' ? rate : BigInt(0);
      const pct = (Number(r) / 1e18) * 100;
      return isFinite(pct) ? `${pct.toFixed(4)}%` : '0.00%';
    } catch { return '0.00%'; }
  };

  const formatCurrency = (value: number): string => {
    if (value >= 1e6) return `$${(value / 1e6).toFixed(2)}M`;
    if (value >= 1e3) return `$${(value / 1e3).toFixed(1)}K`;
    return `$${value.toFixed(0)}`;
  };

  const formatTimeToResolution = (ts: number): string => {
    const diff = ts - Date.now();
    if (diff < 0) return 'Expired';
    const d = Math.floor(diff / 86400000);
    const h = Math.floor((diff % 86400000) / 3600000);
    return d > 0 ? `${d}d ${h}h` : `${h}h`;
  };

  // Candlestick data generation
  useEffect(() => {
    const intervals: Record<TimeFrame, number> = {
      '1m': 60000, '5m': 300000, '15m': 900000,
      '1h': 3600000, '4h': 14400000, '1D': 86400000,
    };
    const counts: Record<TimeFrame, number> = {
      '1m': 60, '5m': 72, '15m': 96, '1h': 168, '4h': 168, '1D': 30,
    };
    const data: CandlestickData[] = [];
    const now = Date.now();
    const interval = intervals[selectedTimeframe];
    const count = counts[selectedTimeframe];
    let price = currentPrice > 0 ? currentPrice : 0.5;

    for (let i = count; i >= 0; i--) {
      const timestamp = now - (i * interval);
      const open = price;
      const close = Math.max(0.01, Math.min(0.99, open + (Math.random() - 0.5) * 0.015));
      const range = Math.abs(close - open);
      const high = Math.min(0.99, Math.max(open, close) + Math.random() * Math.max(range * 1.5, 0.0075));
      const low = Math.max(0.01, Math.min(open, close) - Math.random() * Math.max(range * 1.5, 0.0075));
      const ts = selectedTimeframe === '1D'
        ? new Date(timestamp).toLocaleDateString()
        : new Date(timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      data.push({ time: timestamp, timestamp: ts, open, high, low, close, volume: Math.random() * 100000 + 10000 });
      price = close;
    }
    setCandlestickData(data);
  }, [market?.id, currentPrice, selectedTimeframe]);

  const CandlestickBar = (props: any) => {
    const { payload, x, y, width, height } = props;
    if (!payload?.open || !payload?.close || !x || !height) return null;
    const { open, high, low, close } = payload;
    if ([open, high, low, close, x, y, width, height].some(v => typeof v !== 'number' || !isFinite(v))) return null;
    const isGreen = close >= open;
    const color = isGreen ? '#E6FF2B' : '#FF4868';
    const bodyTop = Math.min(open, close) * height;
    const bodyHeight = Math.abs(close - open) * height;
    const wickX = x + width / 2;
    return (
      <g>
        <line x1={wickX} y1={y + height - high * height} x2={wickX} y2={y + height - low * height} stroke={color} strokeWidth={1} />
        <rect x={x + width * 0.2} y={y + height - bodyTop - bodyHeight} width={width * 0.6}
          height={Math.max(bodyHeight, 1)} fill={isGreen ? color : 'transparent'} stroke={color} strokeWidth={isGreen ? 0 : 1} />
      </g>
    );
  };

  const CustomTooltip = ({ active, payload }: any) => {
    if (!active || !payload?.length) return null;
    const d = payload[0]?.payload;
    if (!d?.open) return null;
    const isGreen = d.close >= d.open;
    return (
      <div className="bg-surface-1 border border-border rounded-lg p-3 shadow-lg">
        <p className="text-gray-400 text-xs mb-2">{d.timestamp}</p>
        <div className="grid grid-cols-2 gap-2 text-xs">
          <div><span className="text-gray-500">O: </span><span className="text-gray-200 font-mono">{(d.open * 100).toFixed(1)}¢</span></div>
          <div><span className="text-gray-500">H: </span><span className="text-gray-200 font-mono">{(d.high * 100).toFixed(1)}¢</span></div>
          <div><span className="text-gray-500">L: </span><span className="text-gray-200 font-mono">{(d.low * 100).toFixed(1)}¢</span></div>
          <div><span className="text-gray-500">C: </span><span className={`font-mono ${isGreen ? 'text-accent' : 'text-danger'}`}>{(d.close * 100).toFixed(1)}¢</span></div>
        </div>
      </div>
    );
  };

  const cat = CATEGORY_COLORS[market?.category || ''] || { bg: 'bg-surface-3', text: 'text-gray-400', border: 'border-border' };
  const timeframes: { value: TimeFrame; label: string }[] = [
    { value: '1m', label: '1M' }, { value: '5m', label: '5M' }, { value: '15m', label: '15M' },
    { value: '1h', label: '1H' }, { value: '4h', label: '4H' }, { value: '1D', label: '1D' },
  ];

  const priceColor = currentPrice >= 0.6 ? 'text-accent' : currentPrice <= 0.4 ? 'text-danger' : 'text-ivory';

  if (!market?.id || typeof market.price !== 'number') {
    return (
      <div className="text-center py-12">
        <p className="text-danger">Invalid market data</p>
        <button onClick={onBack} className="mt-4 px-4 py-2 bg-accent text-surface-0 rounded-md">Back to Markets</button>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      {/* Back button */}
      <div className="flex items-center justify-between">
        <button onClick={onBack} className="flex items-center space-x-2 text-steel hover:text-ivory transition-colors group">
          <svg className="w-4 h-4 group-hover:-translate-x-0.5 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          <span className="text-sm">Back to Markets</span>
        </button>
        <button onClick={refreshProbabilities} className="text-xs text-steel hover:text-ivory px-3 py-1.5 rounded-lg border border-border hover:border-accent/30 transition-all">
          Refresh
        </button>
      </div>

      {/* ═══════ MAIN TWO-COLUMN LAYOUT ═══════ */}
      <div className="flex flex-col lg:flex-row gap-5">

        {/* ═══ LEFT COLUMN — Market info + Chart + Stats ═══ */}
        <div className="flex-1 min-w-0 space-y-5">

          {/* ── Market Header Card ── */}
          <div className="rounded-xl border border-border overflow-hidden" style={{ background: '#0c0d14' }}>
            <div className="p-5">
              {/* Category + Live + Source */}
              <div className="flex items-center space-x-2 mb-3">
                <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-[10px] font-semibold uppercase tracking-wider ${cat.bg} ${cat.text} border ${cat.border}`}>
                  {market.category}
                </span>
                {market.isLive && (
                  <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold bg-accent/10 text-accent border border-accent/20">
                    <span className="w-1.5 h-1.5 bg-accent rounded-full mr-1 animate-pulse" />
                    Live
                  </span>
                )}
                <span className={`text-[10px] font-mono ${hasOracleData ? 'text-accent/60' : 'text-warning/60'}`}>
                  {hasOracleData ? 'Polymarket Oracle' : 'Fallback Data'}
                </span>
              </div>

              {/* Title */}
              <h1 className="text-xl sm:text-2xl font-bold text-ivory mb-4 leading-tight">
                {market.description}
              </h1>

              {/* Key metrics row */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                {/* Probability — hero metric */}
                <div className="col-span-2 sm:col-span-1">
                  <p className="text-[10px] uppercase tracking-wider text-steel mb-1">Probability</p>
                  <p className={`text-3xl font-bold font-mono ${priceColor}`}>
                    {(currentPrice * 100).toFixed(1)}%
                  </p>
                  <p className="text-[10px] text-steel/60 font-mono mt-0.5">
                    {(currentPrice * 100).toFixed(1)}¢ per contract
                  </p>
                </div>

                {/* On-chain Mark Price */}
                <div>
                  <p className="text-[10px] uppercase tracking-wider text-steel mb-1">On-Chain PI</p>
                  {(() => {
                    const isStale = mtmPrice !== null && Math.abs(mtmPrice - currentPrice) > 0.05;
                    return (
                      <>
                        <p className={`text-lg font-bold font-mono ${isStale ? 'text-warning' : 'text-blue-400'}`}>
                          {mtmPrice ? `${(mtmPrice * 100).toFixed(1)}¢` : '—'}
                        </p>
                        <p className={`text-[10px] ${isStale ? 'text-warning/60' : 'text-steel/60'}`}>
                          {isStale ? 'Awaiting keeper update' : 'On-chain smoothed'}
                        </p>
                      </>
                    );
                  })()}
                </div>

                {/* Resolution */}
                <div>
                  <p className="text-[10px] uppercase tracking-wider text-steel mb-1">Resolution</p>
                  <p className="text-lg font-bold text-ivory font-mono">
                    {formatTimeToResolution(market.resolutionTime)}
                  </p>
                  <p className="text-[10px] text-steel/60">Time remaining</p>
                </div>

                {/* Total OI */}
                <div>
                  <p className="text-[10px] uppercase tracking-wider text-steel mb-1">Open Interest</p>
                  <p className="text-lg font-bold text-ivory font-mono">
                    {formatCurrency(totalOI)}
                  </p>
                  <p className="text-[10px] text-steel/60">
                    {marketCapNum > 0 ? `of ${formatCurrency(marketCapNum)} cap` : 'Active'}
                  </p>
                </div>
              </div>
            </div>
          </div>

          {/* ── Price Chart ── */}
          <div className="rounded-xl border border-border p-5" style={{ background: '#0c0d14' }}>
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center space-x-3">
                <h3 className="text-sm font-semibold text-ivory">Price Chart</h3>
                <span className="text-xs text-accent font-mono">{(currentPrice * 100).toFixed(1)}¢</span>
              </div>
              <div className="flex space-x-0.5 bg-surface-2 rounded-md p-0.5">
                {timeframes.map((tf) => (
                  <button key={tf.value} onClick={() => setSelectedTimeframe(tf.value)}
                    className={`px-2.5 py-1 text-[10px] font-semibold rounded transition-all ${
                      selectedTimeframe === tf.value
                        ? 'bg-accent text-surface-0' : 'text-steel hover:text-ivory'
                    }`}>
                    {tf.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="h-72 sm:h-80">
              {candlestickData.length > 0 ? (
                <ResponsiveContainer width="100%" height="100%">
                  <ComposedChart data={candlestickData} margin={{ top: 10, right: 10, left: 0, bottom: 10 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#374151" opacity={0.2} />
                    <XAxis dataKey="timestamp" axisLine={false} tickLine={false} tick={{ fontSize: 9, fill: '#6B7280' }} interval="preserveStartEnd" />
                    <YAxis domain={['dataMin - 0.01', 'dataMax + 0.01']} tickFormatter={(v: number) => `${(v * 100).toFixed(0)}¢`}
                      axisLine={false} tickLine={false} tick={{ fontSize: 9, fill: '#6B7280' }} width={35} />
                    <Tooltip content={<CustomTooltip />} />
                    <Bar dataKey={(entry: CandlestickData) => [entry.low, entry.high]} shape={<CandlestickBar />} />
                    <Line type="monotone" dataKey="close" stroke="transparent" dot={false} strokeWidth={0} />
                  </ComposedChart>
                </ResponsiveContainer>
              ) : (
                <div className="flex items-center justify-center h-full text-steel">Loading chart...</div>
              )}
            </div>

            <div className="flex justify-between text-[10px] text-steel/60 mt-1">
              <span>{selectedTimeframe === '1D' ? 'Last 30 days' : selectedTimeframe === '4h' ? 'Last 4 weeks' :
                selectedTimeframe === '1h' ? 'Last week' : selectedTimeframe === '15m' ? 'Last 24 hours' :
                selectedTimeframe === '5m' ? 'Last 6 hours' : 'Last hour'}</span>
            </div>
          </div>

          {/* ── Liquidity Depth + OI + Rates — Combined Stats Row ── */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">

            {/* Liquidity Depth Visualization */}
            <div className="rounded-xl border border-border p-5" style={{ background: '#0c0d14' }}>
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-sm font-semibold text-ivory">Liquidity Pool</h3>
                <span className="text-[10px] font-mono text-accent/70">{formatCurrency(depthAvailable)} available</span>
              </div>

              {/* Tank + tier markers */}
              <div className="flex gap-4 mb-4">
                {/* The tank vessel */}
                <div className="flex-1 relative h-48 rounded-2xl overflow-hidden"
                  style={{
                    background: 'linear-gradient(180deg, #060810 0%, #080a12 100%)',
                    border: '1px solid rgba(230, 255, 43, 0.1)',
                    boxShadow: 'inset 0 0 30px rgba(230, 255, 43, 0.02), 0 0 1px rgba(230,255,43,0.12)',
                  }}>

                  {/* Empty capacity — subtle grid pattern to show the "container" */}
                  <div className="absolute inset-0" style={{
                    backgroundImage: 'linear-gradient(rgba(230,255,43,0.015) 1px, transparent 1px)',
                    backgroundSize: '100% 12px',
                  }} />

                  {/* Liquid body — rises from bottom */}
                  <div className="absolute bottom-0 left-0 right-0 transition-all duration-[2000ms] ease-out"
                    style={{ height: `${Math.max(depthUsedPct, 3)}%` }}>

                    {/* Primary wave */}
                    <svg className="absolute -top-[7px] left-0 w-[200%]" viewBox="0 0 1200 16" preserveAspectRatio="none"
                      style={{ height: '10px', animation: 'wave-drift 3s linear infinite' }}>
                      <path d="M0,8 Q75,2 150,8 T300,8 T450,8 T600,8 T750,8 T900,8 T1050,8 T1200,8 L1200,16 L0,16 Z"
                        fill={depthUsedPct > 75 ? 'rgba(248,113,113,0.7)' : 'rgba(230,255,43,0.5)'} />
                    </svg>
                    {/* Secondary wave (slower, offset) */}
                    <svg className="absolute -top-[5px] left-0 w-[200%]" viewBox="0 0 1200 14" preserveAspectRatio="none"
                      style={{ height: '8px', animation: 'wave-drift 5s linear infinite reverse' }}>
                      <path d="M0,7 Q100,3 200,7 T400,7 T600,7 T800,7 T1000,7 T1200,7 L1200,14 L0,14 Z"
                        fill={depthUsedPct > 75 ? 'rgba(248,113,113,0.4)' : 'rgba(230,255,43,0.25)'} />
                    </svg>

                    {/* Liquid body */}
                    <div className="absolute inset-0 top-1" style={{
                      background: depthUsedPct > 75
                        ? 'linear-gradient(180deg, rgba(248,113,113,0.35) 0%, rgba(248,113,113,0.12) 60%, rgba(248,113,113,0.06) 100%)'
                        : 'linear-gradient(180deg, rgba(230,255,43,0.25) 0%, rgba(200,230,30,0.12) 40%, rgba(180,210,20,0.04) 100%)',
                    }} />

                    {/* Light refraction / caustics */}
                    <div className="absolute inset-0 top-1 overflow-hidden">
                      <div className="absolute inset-0" style={{
                        backgroundImage: `
                          radial-gradient(ellipse 80px 40px at 25% 30%, rgba(255,255,255,0.07) 0%, transparent 100%),
                          radial-gradient(ellipse 60px 30px at 65% 60%, rgba(255,255,255,0.05) 0%, transparent 100%),
                          radial-gradient(ellipse 50px 25px at 80% 20%, rgba(255,255,255,0.04) 0%, transparent 100%)
                        `,
                        animation: 'caustic-shift 6s ease-in-out infinite alternate',
                      }} />
                    </div>

                    {/* Bubbles — hollow circles that float up */}
                    <div className="absolute bottom-[10%] left-[18%] w-2 h-2 rounded-full border border-white/25"
                      style={{ animation: 'bubble-rise 3s ease-out infinite', boxShadow: 'inset 0 -1px 2px rgba(255,255,255,0.1)' }} />
                    <div className="absolute bottom-[15%] left-[52%] w-1.5 h-1.5 rounded-full border border-white/20"
                      style={{ animation: 'bubble-rise 4s ease-out infinite 1s', boxShadow: 'inset 0 -1px 1px rgba(255,255,255,0.08)' }} />
                    <div className="absolute bottom-[5%] left-[72%] w-1 h-1 rounded-full border border-white/15"
                      style={{ animation: 'bubble-rise 5s ease-out infinite 2.2s' }} />
                    <div className="absolute bottom-[20%] left-[35%] w-1 h-1 rounded-full border border-white/12"
                      style={{ animation: 'bubble-rise 4.5s ease-out infinite 0.5s' }} />
                    <div className="absolute bottom-[8%] left-[88%] w-[5px] h-[5px] rounded-full border border-white/18"
                      style={{ animation: 'bubble-rise 3.5s ease-out infinite 1.8s', boxShadow: 'inset 0 -1px 1px rgba(255,255,255,0.06)' }} />

                    {/* Surface glow line */}
                    <div className="absolute top-0 left-2 right-2 h-[1px]" style={{
                      background: depthUsedPct > 75
                        ? 'linear-gradient(90deg, transparent, rgba(248,113,113,0.6), transparent)'
                        : 'linear-gradient(90deg, transparent, rgba(230,255,43,0.45), transparent)',
                      boxShadow: depthUsedPct > 75
                        ? '0 0 8px rgba(248,113,113,0.3)'
                        : '0 0 8px rgba(230,255,43,0.2)',
                    }} />
                  </div>

                  {/* Side cap marker line inside tank */}
                  {sideCapPct > 5 && sideCapPct < 95 && (
                    <div className="absolute left-3 right-3 flex items-center" style={{ bottom: `${sideCapPct}%` }}>
                      <div className="flex-1 h-[1px] opacity-50"
                        style={{ backgroundImage: 'repeating-linear-gradient(90deg, rgba(168,85,247,0.5) 0px, rgba(168,85,247,0.5) 4px, transparent 4px, transparent 8px)' }} />
                    </div>
                  )}

                  {/* Center percentage */}
                  <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                    <div className="text-center">
                      <p className="text-3xl font-bold font-mono text-white/90"
                        style={{ textShadow: '0 2px 12px rgba(0,0,0,0.95), 0 0 40px rgba(0,0,0,0.8)' }}>
                        {depthUsedPct.toFixed(0)}<span className="text-lg">%</span>
                      </p>
                      <p className="text-[9px] text-white/40 font-semibold tracking-[0.15em] uppercase"
                        style={{ textShadow: '0 1px 6px rgba(0,0,0,0.95)' }}>
                        capacity used
                      </p>
                    </div>
                  </div>
                </div>

                {/* Tier gauge on the right */}
                <div className="w-[88px] relative text-[10px]" style={{ height: '12rem' }}>
                  {/* Vertical track */}
                  <div className="absolute left-0 top-0 bottom-0 w-[3px] rounded-full"
                    style={{ background: 'linear-gradient(180deg, rgba(230,255,43,0.12) 0%, rgba(230,255,43,0.03) 100%)' }} />

                  {/* Fill level on track */}
                  <div className="absolute left-0 bottom-0 w-[3px] rounded-full transition-all duration-[2000ms]"
                    style={{
                      height: `${Math.max(depthUsedPct, 2)}%`,
                      background: depthUsedPct > 75
                        ? 'linear-gradient(180deg, rgba(248,113,113,0.8), rgba(248,113,113,0.3))'
                        : 'linear-gradient(180deg, rgba(230,255,43,0.8), rgba(200,230,30,0.3))',
                      boxShadow: depthUsedPct > 75
                        ? '0 0 6px rgba(248,113,113,0.4)' : '0 0 6px rgba(230,255,43,0.25)',
                    }} />

                  {/* Cap label — top */}
                  <div className="absolute top-0 left-3 flex items-center space-x-1.5">
                    <div className="w-1 h-1 rounded-full bg-accent/50" />
                    <div>
                      <div className="text-accent/60 leading-none">Market Cap</div>
                      <div className="text-accent font-mono font-semibold text-[11px] leading-tight">{formatCurrency(marketCapNum)}</div>
                    </div>
                  </div>

                  {/* Side cap marker */}
                  {sideCapPct > 10 && sideCapPct < 90 && (
                    <div className="absolute left-3 flex items-center space-x-1.5" style={{ bottom: `${sideCapPct}%`, transform: 'translateY(50%)' }}>
                      <div className="w-1 h-1 rounded-full bg-purple/50" />
                      <div>
                        <div className="text-purple/60 leading-none">Side Cap</div>
                        <div className="text-purple/80 font-mono text-[10px] leading-tight">{formatCurrency(sideCapNum)}</div>
                      </div>
                    </div>
                  )}

                  {/* Current OI marker */}
                  <div className="absolute left-3 flex items-center space-x-1.5"
                    style={{ bottom: `${Math.max(depthUsedPct, 2)}%`, transform: 'translateY(50%)' }}>
                    <div className="w-1.5 h-1.5 rounded-full"
                      style={{ background: depthUsedPct > 75 ? '#f87171' : '#E6FF2B', boxShadow: depthUsedPct > 75 ? '0 0 4px #f87171' : '0 0 4px rgba(230,255,43,0.5)' }} />
                    <div>
                      <div className="text-white/50 leading-none">OI</div>
                      <div className="text-white font-mono font-semibold text-[11px] leading-tight">{formatCurrency(totalOI)}</div>
                    </div>
                  </div>
                </div>
              </div>

              {/* Tier breakdown */}
              <div className="grid grid-cols-3 gap-3 pt-3 border-t border-border/20">
                <div className="text-center">
                  <p className="text-[10px] text-steel/50 uppercase tracking-wider mb-0.5">Market</p>
                  <p className="text-sm font-bold font-mono text-ivory">{depthUsedPct.toFixed(0)}%</p>
                  <p className="text-[10px] text-accent/60 font-mono">{formatCurrency(depthAvailable)} free</p>
                </div>
                <div className="text-center border-x border-border/20">
                  <p className="text-[10px] text-steel/50 uppercase tracking-wider mb-0.5">Per-Side</p>
                  <p className="text-sm font-bold font-mono text-ivory">{heavySidePct.toFixed(0)}%</p>
                  <p className="text-[10px] text-purple/60 font-mono">{formatCurrency(sideCapNum)} cap</p>
                </div>
                <div className="text-center">
                  <p className="text-[10px] text-steel/50 uppercase tracking-wider mb-0.5">Global</p>
                  <p className="text-sm font-bold font-mono text-ivory">{globalUsedPct.toFixed(0)}%</p>
                  <p className="text-[10px] text-blue-400/60 font-mono">{formatCurrency(globalCapNum)} cap</p>
                </div>
              </div>
            </div>

            {/* OI Breakdown + Rates */}
            <div className="rounded-xl border border-border p-5 space-y-5" style={{ background: '#0c0d14' }}>
              {/* OI Split */}
              <div>
                <h3 className="text-sm font-semibold text-ivory mb-3">Open Interest</h3>
                {/* OI Bar */}
                <div className="flex h-6 rounded-md overflow-hidden mb-3">
                  <div className="bg-accent/80 flex items-center justify-center text-[10px] font-bold text-surface-0 transition-all"
                    style={{ width: `${Math.max(longPct, 2)}%` }}>
                    {longPct >= 10 ? `${Math.round(longPct)}%` : ''}
                  </div>
                  <div className="bg-danger/80 flex items-center justify-center text-[10px] font-bold text-white transition-all"
                    style={{ width: `${Math.max(shortPct, 2)}%` }}>
                    {shortPct >= 10 ? `${Math.round(shortPct)}%` : ''}
                  </div>
                </div>
                <div className="flex justify-between text-xs">
                  <div>
                    <span className="text-accent font-mono font-semibold">{formatCurrency(longOINum)}</span>
                    <span className="text-steel ml-1">Long</span>
                  </div>
                  <div>
                    <span className="text-steel mr-1">Short</span>
                    <span className="text-danger font-mono font-semibold">{formatCurrency(shortOINum)}</span>
                  </div>
                </div>
              </div>

              {/* Divider */}
              <div className="border-t border-border/50" />

              {/* Rates */}
              <div>
                <h3 className="text-sm font-semibold text-ivory mb-3">Rates</h3>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-[10px] uppercase tracking-wider text-steel mb-1">Funding</p>
                    <p className="text-lg font-bold text-purple font-mono">{formatRate(fundingRate)}</p>
                    <p className="text-[10px] text-steel/60">per hour</p>
                  </div>
                  <div>
                    <p className="text-[10px] uppercase tracking-wider text-steel mb-1">Borrow</p>
                    <p className="text-lg font-bold text-warning font-mono">{formatRate(borrowRate)}</p>
                    <p className="text-[10px] text-steel/60">per hour</p>
                  </div>
                </div>
                <p className="text-[10px] text-steel/50 mt-3">
                  Funding: heavy side pays light side. Borrow: cost for leveraged positions.
                </p>
              </div>
            </div>
          </div>

          {/* ── Recent Trades ── */}
          <div className="rounded-xl border border-border p-5" style={{ background: '#0c0d14' }}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-ivory">Recent Trades</h3>
              <span className="text-[10px] text-steel font-mono">{recentTrades.length} trades</span>
            </div>

            {tradesLoading ? (
              <div className="flex items-center justify-center py-6">
                <div className="animate-spin w-5 h-5 border-2 border-accent border-t-transparent rounded-full" />
                <span className="text-xs text-steel ml-2">Fetching on-chain trades...</span>
              </div>
            ) : recentTrades.length === 0 ? (
              <div className="text-center py-6">
                <p className="text-steel text-sm">No trades found for this market yet</p>
                <p className="text-[10px] text-steel/50 mt-1">Be the first to open a position!</p>
              </div>
            ) : (
              <div className="space-y-0">
                {/* Header row */}
                <div className="grid grid-cols-12 gap-2 text-[10px] uppercase tracking-wider text-steel/60 pb-2 border-b border-border/30">
                  <div className="col-span-1">Side</div>
                  <div className="col-span-3">Trader</div>
                  <div className="col-span-2 text-right">Size</div>
                  <div className="col-span-2 text-right">Leverage</div>
                  <div className="col-span-2 text-right">Entry</div>
                  <div className="col-span-2 text-right">Time</div>
                </div>

                {recentTrades.map((trade) => {
                  const shortAddr = `${trade.owner.slice(0, 6)}...${trade.owner.slice(-4)}`;
                  const size = Number(trade.positionSize) / 1e6;
                  const lev = Number(trade.leverage) / 1e18;
                  const entry = Number(trade.entryPrice) / 1e18 * 100;
                  const ts = Number(trade.timestamp) * 1000;
                  const now = Date.now();
                  const diff = Math.floor((now - ts) / 1000);
                  const timeAgo = diff < 60 ? 'Just now' : diff < 3600 ? `${Math.floor(diff / 60)}m ago` :
                    diff < 86400 ? `${Math.floor(diff / 3600)}h ago` : `${Math.floor(diff / 86400)}d ago`;
                  const explorerUrl = `https://sepolia.basescan.org/tx/${trade.txHash}`;

                  return (
                    <a
                      key={trade.txHash + trade.positionId}
                      href={explorerUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="grid grid-cols-12 gap-2 py-2 text-xs hover:bg-white/[0.02] transition-colors border-b border-border/10 last:border-0 group cursor-pointer"
                    >
                      <div className="col-span-1">
                        <span className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-bold ${
                          trade.isLong
                            ? 'bg-accent/10 text-accent'
                            : 'bg-danger/10 text-danger'
                        }`}>
                          {trade.isLong ? 'L' : 'S'}
                        </span>
                      </div>
                      <div className="col-span-3">
                        <span className="font-mono text-steel group-hover:text-ivory transition-colors">
                          {shortAddr}
                        </span>
                      </div>
                      <div className="col-span-2 text-right">
                        <span className="font-mono text-ivory">${size >= 1000 ? `${(size / 1000).toFixed(1)}K` : size.toFixed(0)}</span>
                      </div>
                      <div className="col-span-2 text-right">
                        <span className="font-mono text-steel">{lev.toFixed(1)}x</span>
                      </div>
                      <div className="col-span-2 text-right">
                        <span className="font-mono text-steel">{entry.toFixed(1)}¢</span>
                      </div>
                      <div className="col-span-2 text-right flex items-center justify-end space-x-1">
                        <span className="text-steel/60">{timeAgo}</span>
                        <svg className="w-3 h-3 text-steel/30 group-hover:text-accent transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                        </svg>
                      </div>
                    </a>
                  );
                })}
              </div>
            )}
          </div>
        </div>

        {/* ═══ RIGHT COLUMN — Sticky Trade Form ═══ */}
        <div className="lg:w-80 xl:w-96 flex-shrink-0">
          <div className="lg:sticky lg:top-4">
            <div className="rounded-xl border border-border p-5" style={{ background: '#0c0d14' }}>
              <TradeForm
                marketId={marketBytes32}
                marketName={market.description}
                currentPrice={currentPrice}
                onTradeSelect={onTradeSelect}
                compact={true}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default MarketDetail;
