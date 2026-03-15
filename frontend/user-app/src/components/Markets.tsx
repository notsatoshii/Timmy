import React, { useState, useEffect, useMemo } from 'react';
import { useReadContract } from 'wagmi';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import { MARKET_REGISTRY_ABI, ORACLE_ADAPTER_ABI } from '../config/abis';
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

interface MarketsProps {
  onTradeSelect?: (marketId: string, marketName: string, direction: 'long' | 'short') => void;
}

const Markets: React.FC<MarketsProps> = ({ onTradeSelect }) => {
  const [markets, setMarkets] = useState<Market[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Read active markets from MarketRegistry
  const { data: activeMarketIds, isLoading: loadingMarketIds } = useReadContract({
    address: CONTRACT_ADDRESSES.marketRegistry,
    abi: MARKET_REGISTRY_ABI,
    functionName: 'getActiveMarkets',
  });

  // Demo market IDs for live price updates
  const demoMarketIds = [
    'demo-1', 'demo-2', 'demo-3', 'demo-4', 'demo-5',
    'demo-6', 'demo-7', 'demo-8', 'demo-9', 'demo-10'
  ];

  // Live price updates (30-second polling)
  const { prices: livePrices, lastUpdate, refreshPrices } = useLivePrices({
    marketIds: demoMarketIds,
    pollingInterval: 30000, // 30 seconds
    enabled: true,
  });

  // Category mapping from contract enum to display strings
  const categoryMap: { [key: number]: string } = {
    0: 'Technology',
    1: 'Geopolitics',
    2: 'Speculative',
    3: 'Sports',
    4: 'Economy',
    5: 'Crypto',
    6: 'Forex',
    7: 'Stocks',
    8: 'Other'
  };

  // Base market data
  const baseMarkets = useMemo(() => [
    {
      id: 'demo-1',
      description: 'Largest IPO by Market Cap 2026: SpaceX?',
      resolutionTime: new Date('2026-12-30').getTime(),
      category: 'Technology',
      isLive: true,
    },
    {
      id: 'demo-2',
      description: 'US-Iran Ceasefire by April 30, 2026?',
      resolutionTime: new Date('2026-04-30').getTime(),
      category: 'Geopolitics',
      isLive: true,
    },
    {
      id: 'demo-3',
      description: 'Nothing Ever Happens: 2026',
      resolutionTime: new Date('2026-12-30').getTime(),
      category: 'Speculative',
      isLive: true,
    },
    {
      id: 'demo-4',
      description: '2026 FIFA World Cup Winner: Spain?',
      resolutionTime: new Date('2026-07-19').getTime(),
      category: 'Sports',
      isLive: true,
    },
    {
      id: 'demo-5',
      description: 'Fed Rate End of 2026: Below 4%?',
      resolutionTime: new Date('2026-12-08').getTime(),
      category: 'Economy',
      isLive: true,
    },
    {
      id: 'demo-6',
      description: 'SpaceX IPO via Ackman SPAR?',
      resolutionTime: new Date('2026-12-31').getTime(),
      category: 'Technology',
      isLive: true,
    },
    {
      id: 'demo-7',
      description: 'AAPL Above $250 in April 2026?',
      resolutionTime: new Date('2026-04-30').getTime(),
      category: 'Stocks',
      isLive: true,
    },
    {
      id: 'demo-8',
      description: 'OpenSea Token Launch by 2026?',
      resolutionTime: new Date('2026-12-31').getTime(),
      category: 'Crypto',
      isLive: true,
    },
    {
      id: 'demo-9',
      description: 'Fed April 2026: Rate Cut?',
      resolutionTime: new Date('2026-04-28').getTime(),
      category: 'Economy',
      isLive: true,
    },
    {
      id: 'demo-10',
      description: 'Argentina USD Rate Above 1500 ARS End of 2026?',
      resolutionTime: new Date('2026-12-31').getTime(),
      category: 'Forex',
      isLive: true,
    },
  ], []);

  // Combine base market data with live prices
  useEffect(() => {
    const marketsWithLivePrices = baseMarkets.map(market => ({
      ...market,
      price: livePrices[market.id]?.pi || 0.5,
    }));

    setMarkets(marketsWithLivePrices);
    setIsLoading(false);
  }, [baseMarkets, livePrices]);

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
    if (price >= 0.6) return 'text-success-600';
    if (price <= 0.4) return 'text-danger-600';
    return 'text-gray-600';
  };

  const getCategoryColor = (category: string): string => {
    const colors: { [key: string]: string } = {
      'Politics': 'bg-blue-100 text-blue-800',
      'Sports': 'bg-green-100 text-green-800',
      'Technology': 'bg-purple-100 text-purple-800',
      'Economy': 'bg-yellow-100 text-yellow-800',
      'Crypto': 'bg-orange-100 text-orange-800',
      'Entertainment': 'bg-pink-100 text-pink-800',
      'Weather': 'bg-indigo-100 text-indigo-800',
      'Other': 'bg-gray-100 text-gray-800',
      'Geopolitics': 'bg-red-100 text-red-800',
      'Speculative': 'bg-indigo-100 text-indigo-800',
      'Stocks': 'bg-blue-100 text-blue-800',
      'Forex': 'bg-green-100 text-green-800',
    };
    return colors[category] || colors['Other'];
  };

  const formatLastUpdateTime = (timestamp: number): string => {
    if (!timestamp) return '';
    const now = Date.now();
    const diff = Math.floor((now - timestamp) / 1000); // seconds

    if (diff < 60) return 'Just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    return `${Math.floor(diff / 3600)}h ago`;
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">Prediction Markets</h2>
          <p className="text-gray-600">
            Browse active binary outcome markets with up to 30x leverage
          </p>
        </div>
        <div className="text-right">
          <div className="flex items-center justify-end space-x-3">
            <div className="flex items-center space-x-2">
              <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
              <span className="text-sm text-green-600 font-medium">Live Prices</span>
            </div>
            <button
              onClick={refreshPrices}
              className="text-sm text-gray-500 hover:text-gray-700 px-2 py-1 rounded border border-gray-200 hover:border-gray-300 transition-colors"
            >
              Refresh
            </button>
          </div>
          <p className="text-sm text-gray-600 mt-1">
            Showing {markets.length} active markets
          </p>
          {lastUpdate > 0 && (
            <p className="text-xs text-gray-500">
              Updated {formatLastUpdateTime(lastUpdate)}
            </p>
          )}
        </div>
      </div>

      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-1">
        {markets.map((market) => (
          <div
            key={market.id}
            className="bg-white rounded-lg shadow-sm border border-gray-200 p-6 hover:shadow-md transition-shadow duration-200"
          >
            <div className="flex items-start justify-between">
              <div className="flex-1 min-w-0">
                <div className="flex items-center space-x-3 mb-3">
                  <span
                    className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getCategoryColor(market.category)}`}
                  >
                    {market.category}
                  </span>
                  {market.isLive && (
                    <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
                      <div className="w-2 h-2 bg-green-400 rounded-full mr-1"></div>
                      Live
                    </span>
                  )}
                </div>

                <h3 className="text-lg font-semibold text-gray-900 mb-2">
                  {market.description}
                </h3>

                <div className="grid grid-cols-3 gap-4 text-sm">
                  <div>
                    <p className="text-gray-500 flex items-center">
                      Current Price
                      {livePrices[market.id] && (
                        <span className="ml-1 w-1.5 h-1.5 bg-green-400 rounded-full animate-pulse"></span>
                      )}
                    </p>
                    <p className={`font-semibold transition-all duration-300 ${getPriceColor(market.price)}`}>
                      ${(market.price * 100).toFixed(1)}¢
                    </p>
                  </div>
                  <div>
                    <p className="text-gray-500">Probability</p>
                    <p className="font-semibold text-gray-900 transition-all duration-300">
                      {(market.price * 100).toFixed(1)}%
                    </p>
                  </div>
                  <div>
                    <p className="text-gray-500">Resolution</p>
                    <p className="font-semibold text-gray-900">
                      {formatTimeToResolution(market.resolutionTime)}
                    </p>
                  </div>
                </div>
              </div>

              <div className="ml-6 flex-shrink-0">
                <div className="flex space-x-2">
                  <button
                    onClick={() => onTradeSelect?.(market.id, market.description, 'long')}
                    className="bg-success-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-success-700 transition-colors"
                  >
                    Long
                  </button>
                  <button
                    onClick={() => onTradeSelect?.(market.id, market.description, 'short')}
                    className="bg-danger-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-danger-700 transition-colors"
                  >
                    Short
                  </button>
                </div>
                <p className="text-xs text-gray-500 text-center mt-2">
                  Up to 30x leverage
                </p>
              </div>
            </div>
          </div>
        ))}
      </div>

      {isLoading && (
        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-1">
          {[1, 2, 3].map((index) => (
            <div key={index} className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
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
          <p className="text-sm text-gray-400 mt-2">
            Markets will appear here once they are created
          </p>
        </div>
      )}
    </div>
  );
};

export default Markets;
