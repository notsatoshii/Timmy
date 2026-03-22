import React, { useMemo } from 'react';
import { useReadContract } from 'wagmi';
import { useMarketProbabilities } from '../hooks/useMarketProbabilities';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import { LEVERAGE_MODEL_ABI } from '../config/abis';
import ProfessionalLoader from './ProfessionalLoader';
import TestnetDisclaimer from './TestnetDisclaimer';
import { LiveDataBadge } from './ConnectionStatus';

interface Market {
  id: string;
  description: string;
  price: number;
  resolutionTime: number;
  category: string;
  isLive: boolean;
  source?: 'oracle' | 'fallback';
}

interface MarketsProps {
  onTradeSelect?: (marketId: string, marketName: string, direction: 'long' | 'short') => void;
  onMarketDetail?: (market: Market) => void;
}

const CATEGORY_COLORS: Record<string, string> = {
  Technology: '#3B82F6',
  Geopolitics: '#EF4444',
  Economy: '#F59E0B',
  Sports: '#10B981',
  Crypto: '#8B5CF6',
  Stocks: '#06B6D4',
  Forex: '#EC4899',
  Speculative: '#6B7280',
  Politics: '#8B5CF6',
  Entertainment: '#EC4899',
  Other: '#6B7280',
};

const Markets: React.FC<MarketsProps> = ({ onTradeSelect, onMarketDetail }) => {
  const { data: maxLeverageRaw } = useReadContract({
    address: CONTRACT_ADDRESSES.leverageModel,
    abi: LEVERAGE_MODEL_ABI,
    functionName: 'getEffectiveMaxLeverage',
    args: ['0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1'],
  });
  const maxLevDisplay = maxLeverageRaw ? `${(Number(maxLeverageRaw) / 1e18).toFixed(0)}x` : '...';

  const {
    markets: marketData,
    isLoading,
    lastUpdate,
    refreshProbabilities,
    hasOracleData
  } = useMarketProbabilities({
    pollingInterval: 30000,
    enabled: true,
  });

  const markets = useMemo(() =>
    marketData.map(market => ({
      id: market.id,
      description: market.name,
      price: market.probability,
      resolutionTime: market.expiryTimestamp,
      category: market.category,
      isLive: market.isLive,
      source: market.source,
    }))
  , [marketData]);

  const formatTimeToResolution = (timestamp: number): string => {
    const now = new Date().getTime();
    const diff = timestamp - now;
    if (diff < 0) return 'Expired';
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
    if (days > 0) return `${days}d ${hours}h`;
    return `${hours}h`;
  };

  const getPriceColor = (price: number): string => {
    if (price >= 0.6) return '#E6FF2B';
    if (price <= 0.4) return '#EF4444';
    return '#F5F5F7';
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col space-y-4 md:flex-row md:justify-between md:items-center md:space-y-0">
        <div>
          <h2 className="text-2xl font-bold text-ivory">Prediction Markets</h2>
          <p className="text-sm text-steel mt-1">
            {markets.length} active markets · Up to <span className="text-accent font-semibold">{maxLevDisplay}</span> leverage
          </p>
        </div>
        <div className="flex items-center space-x-3">
          <LiveDataBadge />
          <div className="flex items-center space-x-1.5">
            <div className={`w-1.5 h-1.5 rounded-full ${hasOracleData ? 'bg-accent' : 'bg-warning'}`}
              style={hasOracleData ? { animation: 'pulse-glow 2s ease-in-out infinite' } : {}}
            />
            <span className={`text-xs font-medium ${hasOracleData ? 'text-accent' : 'text-warning'}`}>
              {hasOracleData ? 'Oracle Active' : 'Fallback'}
            </span>
          </div>
          <button
            onClick={refreshProbabilities}
            className="text-xs text-steel hover:text-ivory px-3 py-1.5 rounded-lg border border-white/4 hover:border-white/8 transition-all"
          >
            Refresh
          </button>
        </div>
      </div>

      <TestnetDisclaimer compact={true} context="general" />

      {/* Market Tile Grid */}
      <div className="grid gap-4 grid-cols-1 md:grid-cols-2 lg:grid-cols-3">
        {markets.map((market) => {
          const catColor = CATEGORY_COLORS[market.category] || CATEGORY_COLORS.Other;
          return (
            <div
              key={market.id}
              data-market-tile={market.id}
              onClick={() => onMarketDetail?.(market)}
              className="cursor-pointer transition-all duration-200 hover:bg-[#161721] group"
              style={{
                background: '#101118',
                border: '1px solid rgba(255,255,255,0.04)',
                borderRadius: '12px',
                padding: '16px',
                borderLeft: '3px solid transparent',
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLElement).style.borderLeftColor = '#E6FF2B';
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLElement).style.borderLeftColor = 'transparent';
              }}
            >
              {/* Top row: category + live */}
              <div className="flex items-center justify-between mb-3">
                <span
                  className="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-medium uppercase tracking-wider"
                  style={{
                    backgroundColor: `${catColor}15`,
                    color: catColor,
                    border: `1px solid ${catColor}30`,
                  }}
                >
                  {market.category}
                </span>
                {market.isLive && (
                  <span className="inline-flex items-center text-[10px] font-medium text-accent">
                    <span
                      className="w-1.5 h-1.5 rounded-full bg-accent mr-1"
                      style={{ animation: 'pulse-glow 2s ease-in-out infinite' }}
                    />
                    Live
                  </span>
                )}
              </div>

              {/* Market name */}
              <h3 className="text-sm font-semibold text-ivory mb-3 leading-snug line-clamp-2 min-h-[2.5rem]">
                {market.description}
              </h3>

              {/* Probability (large) */}
              <div className="mb-3">
                <span
                  className="text-2xl font-bold font-mono"
                  style={{ color: getPriceColor(market.price) }}
                >
                  {(market.price * 100).toFixed(1)}%
                </span>
              </div>

              {/* Stats row */}
              <div className="flex items-center justify-between text-[11px] mb-3"
                style={{
                  background: '#161721',
                  border: '1px solid rgba(255,255,255,0.08)',
                  borderRadius: '8px',
                  padding: '8px 10px',
                }}
              >
                <div>
                  <span className="text-steel uppercase tracking-wider font-medium" style={{ fontSize: '10px', letterSpacing: '0.05em' }}>
                    Resolution
                  </span>
                  <p className="text-ivory font-mono font-semibold mt-0.5">
                    {formatTimeToResolution(market.resolutionTime)}
                  </p>
                </div>
                <div className="text-right">
                  <span className="text-steel uppercase tracking-wider font-medium" style={{ fontSize: '10px', letterSpacing: '0.05em' }}>
                    Max Lev
                  </span>
                  <p className="text-ivory font-mono font-semibold mt-0.5">
                    {maxLevDisplay}
                  </p>
                </div>
              </div>

              {/* Long/Short buttons */}
              <div className="flex space-x-2">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onTradeSelect?.(market.id, market.description, 'long');
                  }}
                  className="flex-1 py-2 rounded-lg text-xs font-semibold text-accent border border-accent/20 bg-accent/5 hover:bg-accent/15 transition-all"
                >
                  Long
                </button>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onTradeSelect?.(market.id, market.description, 'short');
                  }}
                  className="flex-1 py-2 rounded-lg text-xs font-semibold text-danger border border-danger/20 bg-danger/5 hover:bg-danger/15 transition-all"
                >
                  Short
                </button>
              </div>
            </div>
          );
        })}
      </div>

      {isLoading && (
        <ProfessionalLoader
          title="Loading Markets"
          subtitle="Fetching market data and oracle price feeds"
          variant="default"
          size="lg"
          showLiveIndicators={true}
          showProgress={false}
        />
      )}

      {!isLoading && markets.length === 0 && (
        <div className="text-center py-12" style={{ background: '#101118', borderRadius: '12px', border: '1px solid rgba(255,255,255,0.04)' }}>
          <p className="text-steel">No active markets found</p>
          <p className="text-xs text-steel mt-2">Markets will appear here once they are created</p>
        </div>
      )}

      <style>{`
        @keyframes pulse-glow {
          0%, 100% { opacity: 0.4; }
          50% { opacity: 1; }
        }
        .line-clamp-2 {
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
      `}</style>
    </div>
  );
};

export default Markets;
