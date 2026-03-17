import React, { useMemo } from 'react';
import { useMarketProbabilities } from '../hooks/useMarketProbabilities';
import Skeleton from './Skeleton';

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
  // Use new hook that reads from OracleAdapter with demo_markets.json fallback
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

  // Transform market data to component format
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
    return 'text-gray-300';
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
      <div className="flex flex-col space-y-4 md:flex-row md:justify-between md:items-center md:space-y-0">
        <div>
          <h2 className="text-2xl font-bold text-gray-100">Prediction Markets</h2>
          <p className="text-gray-500">
            Browse active binary outcome markets with up to 12x leverage
          </p>
        </div>
        <div className="flex flex-col space-y-3 md:text-right">
          <div className="flex items-center justify-start md:justify-end space-x-3">
            <div className="flex items-center space-x-2">
              <div className={`w-2 h-2 rounded-full animate-pulse ${hasOracleData ? 'bg-accent' : 'bg-warning'}`}></div>
              <span className={`text-sm font-medium ${hasOracleData ? 'text-accent' : 'text-warning'}`}>
                {hasOracleData ? 'Live Oracle' : 'Demo Fallback'}
              </span>
            </div>
            <button
              onClick={refreshProbabilities}
              className="text-sm text-gray-500 hover:text-gray-300 px-2 py-1 rounded border border-border hover:border-border-light transition-colors"
            >
              Refresh
            </button>
          </div>
          <div className="text-left md:text-right">
            <p className="text-sm text-gray-500">
              Showing {markets.length} active markets
            </p>
            <p className="text-xs text-gray-600">
              Source: {hasOracleData ? 'OracleAdapter contract' : 'demo_markets.json fallback'}
            </p>
            {lastUpdate > 0 && (
              <p className="text-xs text-gray-600">
                Updated {formatLastUpdateTime(lastUpdate)}
              </p>
            )}
          </div>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-1">
        {markets.map((market) => (
          <div
            key={market.id}
            className="bg-surface-1 rounded-lg border border-border p-5 hover:border-border-light transition-all duration-200 hover:shadow-card cursor-pointer"
            onClick={() => onMarketDetail?.(market)}
          >
            <div className="flex flex-col space-y-4 md:flex-row md:items-start md:justify-between md:space-y-0">
              <div className="flex-1 min-w-0">
                <div className="flex items-center space-x-3 mb-3">
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

                <h3 className="text-lg font-semibold text-gray-100 mb-3">
                  {market.description}
                </h3>

                <div className="grid grid-cols-2 gap-4 text-sm sm:grid-cols-3">
                  <div>
                    <p className="text-gray-500 flex items-center text-xs uppercase tracking-wide">
                      Price
                      <span className={`ml-1 w-1.5 h-1.5 rounded-full animate-pulse ${
                        market.source === 'oracle' ? 'bg-accent' : 'bg-warning'
                      }`}></span>
                    </p>
                    <p className={`font-semibold font-mono text-lg transition-all duration-300 ${getPriceColor(market.price)}`}>
                      {(market.price * 100).toFixed(1)}¢
                    </p>
                  </div>
                  <div>
                    <p className="text-gray-500 text-xs uppercase tracking-wide">Probability</p>
                    <p className="font-semibold font-mono text-lg text-gray-200 transition-all duration-300">
                      {(market.price * 100).toFixed(1)}%
                    </p>
                  </div>
                  <div className="col-span-2 sm:col-span-1">
                    <p className="text-gray-500 text-xs uppercase tracking-wide">Resolution</p>
                    <p className="font-semibold font-mono text-lg text-gray-200">
                      {formatTimeToResolution(market.resolutionTime)}
                    </p>
                  </div>
                </div>
              </div>

              <div className="md:ml-6 flex-shrink-0">
                <div className="flex space-x-2">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onTradeSelect?.(market.id, market.description, 'long');
                    }}
                    className="bg-accent/10 text-accent border border-accent/30 px-5 py-2 rounded-md text-sm font-semibold hover:bg-accent/20 hover:border-accent/50 transition-all flex-1 md:flex-none"
                  >
                    Long
                  </button>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onTradeSelect?.(market.id, market.description, 'short');
                    }}
                    className="bg-danger/10 text-danger border border-danger/30 px-5 py-2 rounded-md text-sm font-semibold hover:bg-danger/20 hover:border-danger/50 transition-all flex-1 md:flex-none"
                  >
                    Short
                  </button>
                </div>
                <p className="text-xs text-gray-600 text-center mt-2">
                  Up to 12x leverage
                </p>
              </div>
            </div>
          </div>
        ))}
      </div>

      {isLoading && (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-1">
          {[1, 2, 3].map((index) => (
            <div key={index} className="bg-surface-1 rounded-lg border border-border p-5">
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center space-x-3 mb-3">
                    <Skeleton width="80px" height="24px" />
                    <Skeleton width="40px" height="24px" />
                  </div>

                  <Skeleton height="28px" className="mb-2" />
                  <Skeleton width="60%" height="20px" className="mb-4" />

                  <div className="grid grid-cols-3 gap-4">
                    <div>
                      <Skeleton width="80px" height="16px" className="mb-1" />
                      <Skeleton width="60px" height="20px" />
                    </div>
                    <div>
                      <Skeleton width="70px" height="16px" className="mb-1" />
                      <Skeleton width="50px" height="20px" />
                    </div>
                    <div>
                      <Skeleton width="65px" height="16px" className="mb-1" />
                      <Skeleton width="40px" height="20px" />
                    </div>
                  </div>
                </div>

                <div className="ml-6 flex-shrink-0">
                  <div className="flex space-x-2">
                    <Skeleton width="60px" height="36px" />
                    <Skeleton width="60px" height="36px" />
                  </div>
                  <Skeleton width="90px" height="16px" className="mt-2 mx-auto" />
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {!isLoading && markets.length === 0 && (
        <div className="text-center py-12">
          <p className="text-gray-500">No active markets found</p>
          <p className="text-sm text-gray-600 mt-2">
            Markets will appear here once they are created
          </p>
        </div>
      )}
    </div>
  );
};

export default Markets;
