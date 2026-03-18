import React, { useMemo } from 'react';
import { useMarketProbabilities } from '../hooks/useMarketProbabilities';
import Skeleton from './Skeleton';
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

const Markets: React.FC<MarketsProps> = ({ onTradeSelect, onMarketDetail }) => {
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
    if (price >= 0.6) return 'text-accent';
    if (price <= 0.4) return 'text-danger';
    return 'text-ivory';
  };

  const getCategoryColor = (category: string): string => {
    const colors: { [key: string]: string } = {
      'Politics': 'text-purple border-purple/20',
      'Sports': 'text-accent border-accent/20',
      'Technology': 'text-accent border-accent/20',
      'Economy': 'text-warning border-warning/20',
      'Crypto': 'text-warning border-warning/20',
      'Entertainment': 'text-purple border-purple/20',
      'Other': 'text-steel border-border-light',
      'Geopolitics': 'text-danger border-danger/20',
      'Speculative': 'text-purple border-purple/20',
      'Stocks': 'text-accent border-accent/20',
      'Forex': 'text-accent border-accent/20',
    };
    return colors[category] || colors['Other'];
  };

  const formatLastUpdateTime = (timestamp: number): string => {
    if (!timestamp) return '';
    const now = Date.now();
    const diff = Math.floor((now - timestamp) / 1000);
    if (diff < 60) return 'Just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    return `${Math.floor(diff / 3600)}h ago`;
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col space-y-4 md:flex-row md:justify-between md:items-center md:space-y-0">
        <div>
          <h2 className="text-2xl font-bold font-display text-ivory">Prediction Markets</h2>
          <p className="text-sm text-steel mt-1">
            Browse active binary outcome markets with up to <span className="text-accent font-semibold">30x</span> leverage
          </p>
        </div>
        <div className="flex items-center space-x-3">
          <LiveDataBadge />
          <div className="flex items-center space-x-1.5">
            <div className={`w-1.5 h-1.5 rounded-full ${hasOracleData ? 'bg-accent' : 'bg-warning animate-pulse'}`}></div>
            <span className={`text-xs font-medium ${hasOracleData ? 'text-accent' : 'text-warning'}`}>
              {hasOracleData ? 'Oracle Active' : 'Fallback Data'}
            </span>
            {lastUpdate > 0 && (
              <span className={`text-xs ${hasOracleData ? 'text-steel' : 'text-warning/70'} font-mono`}>
                • {formatLastUpdateTime(lastUpdate)}
              </span>
            )}
          </div>
          <button
            onClick={refreshProbabilities}
            className="text-xs text-steel hover:text-ivory px-3 py-1.5 rounded-lg border border-border-light hover:border-border-hover transition-all"
          >
            Refresh
          </button>
        </div>
      </div>

      {/* Testnet Notice */}
      <TestnetDisclaimer compact={true} context="general" />

      {/* Subtitle info */}
      <div className="flex items-center space-x-4 text-xs text-steel">
        <span>{markets.length} active markets</span>
        {lastUpdate > 0 && (
          <>
            <span className="text-border-light">·</span>
            <span>Last update: {formatLastUpdateTime(lastUpdate)}</span>
            <span className="text-border-light">·</span>
            <span className="font-mono text-steel/70">
              {new Date(lastUpdate).toLocaleTimeString()}
            </span>
          </>
        )}
      </div>

      {/* Market Cards */}
      <div className="grid gap-4 lg:grid-cols-1">
        {markets.map((market, index) => (
          <div
            key={market.id}
            className={`${index === 0 ? 'lever-card-glow' : 'lever-card'} cursor-pointer transition-all duration-200 hover:-translate-y-0.5`}
            style={index !== 0 ? {} : {}}
            onClick={() => onMarketDetail?.(market)}
          >
            {/* Category + Live badge */}
            <div className="flex items-center space-x-2 mb-4">
              <span className={`inline-flex items-center px-2.5 py-1 rounded-md text-[10px] font-medium uppercase tracking-wider border lever-inset ${getCategoryColor(market.category)}`}>
                {market.category}
              </span>
              {market.isLive && (
                <span className="inline-flex items-center px-2.5 py-1 rounded-md text-[10px] font-medium uppercase tracking-wider bg-accent/10 text-accent border border-accent/20">
                  <div className="w-1.5 h-1.5 bg-accent rounded-full mr-1.5 animate-pulse"></div>
                  Live
                </span>
              )}
            </div>

            {/* Market Title */}
            <h3 className="text-lg font-semibold font-display text-ivory mb-4 leading-snug">
              {market.description}
            </h3>

            {/* Stats Row — Price, Probability, Resolution in inset boxes */}
            <div className="grid grid-cols-3 gap-3 mb-4">
              <div className="lever-inset">
                <p className="text-[10px] uppercase tracking-widest text-steel mb-1 flex items-center">
                  Price
                  <span className={`ml-1.5 w-1 h-1 rounded-full ${market.source === 'oracle' ? 'bg-accent animate-pulse' : 'bg-warning'}`}></span>
                </p>
                <p className={`font-semibold font-mono text-xl ${getPriceColor(market.price)}`}>
                  {(market.price * 100).toFixed(1)}¢
                </p>
              </div>
              <div className="lever-inset">
                <p className="text-[10px] uppercase tracking-widest text-steel mb-1">Probability</p>
                <p className="font-semibold font-mono text-xl text-ivory">
                  {(market.price * 100).toFixed(1)}%
                </p>
              </div>
              <div className="lever-inset">
                <p className="text-[10px] uppercase tracking-widest text-steel mb-1">Resolution</p>
                <p className="font-semibold font-mono text-xl text-ivory">
                  {formatTimeToResolution(market.resolutionTime)}
                </p>
              </div>
            </div>

            {/* Action Row */}
            <div className="flex items-center space-x-3">
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onTradeSelect?.(market.id, market.description, 'long');
                }}
                className="flex-1 py-2.5 rounded-lg text-sm font-semibold text-accent border border-accent/20 bg-accent/5 hover:bg-accent/15 hover:border-accent/40 hover:shadow-glow-green transition-all"
              >
                Long
              </button>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onTradeSelect?.(market.id, market.description, 'short');
                }}
                className="flex-1 py-2.5 rounded-lg text-sm font-semibold text-danger border border-danger/20 bg-danger/5 hover:bg-danger/15 hover:border-danger/40 transition-all"
              >
                Short
              </button>
              <span className="text-[10px] text-steel uppercase tracking-wider hidden sm:block">30x max</span>
            </div>
          </div>
        ))}
      </div>

      {/* Loading skeletons */}
      {isLoading && (
        <div className="grid gap-4 lg:grid-cols-1">
          {[1, 2, 3].map((index) => (
            <div key={index} className="lever-card">
              <div className="flex items-center space-x-3 mb-4">
                <Skeleton width="80px" height="24px" />
                <Skeleton width="50px" height="24px" />
              </div>
              <Skeleton height="24px" className="mb-4" />
              <div className="grid grid-cols-3 gap-3 mb-4">
                <div className="lever-inset"><Skeleton height="40px" /></div>
                <div className="lever-inset"><Skeleton height="40px" /></div>
                <div className="lever-inset"><Skeleton height="40px" /></div>
              </div>
              <div className="flex space-x-3">
                <Skeleton height="40px" className="flex-1" />
                <Skeleton height="40px" className="flex-1" />
              </div>
            </div>
          ))}
        </div>
      )}

      {!isLoading && markets.length === 0 && (
        <div className="lever-card text-center py-12">
          <p className="text-steel">No active markets found</p>
          <p className="text-xs text-steel mt-2">Markets will appear here once they are created</p>
        </div>
      )}
    </div>
  );
};

export default Markets;
