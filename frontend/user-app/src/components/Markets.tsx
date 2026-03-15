import React, { useState, useEffect, useMemo } from 'react';
import { useReadContract } from 'wagmi';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import { MARKET_REGISTRY_ABI, ORACLE_ADAPTER_ABI } from '../config/abis';

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

  useEffect(() => {
    if (!activeMarketIds || loadingMarketIds || activeMarketIds.length === 0) {
      // If no markets found or still loading, show demo markets with real names from demo_markets.json
      setMarkets([
        {
          id: 'demo-1',
          description: 'Largest IPO by Market Cap 2026: SpaceX?',
          price: 0.88,
          resolutionTime: new Date('2026-12-30').getTime(),
          category: 'Technology',
          isLive: true,
        },
        {
          id: 'demo-2',
          description: 'US-Iran Ceasefire by April 30, 2026?',
          price: 0.35,
          resolutionTime: new Date('2026-04-30').getTime(),
          category: 'Geopolitics',
          isLive: true,
        },
        {
          id: 'demo-3',
          description: 'Nothing Ever Happens: 2026',
          price: 0.42,
          resolutionTime: new Date('2026-12-30').getTime(),
          category: 'Speculative',
          isLive: true,
        },
        {
          id: 'demo-4',
          description: '2026 FIFA World Cup Winner: Spain?',
          price: 0.22,
          resolutionTime: new Date('2026-07-19').getTime(),
          category: 'Sports',
          isLive: true,
        },
        {
          id: 'demo-5',
          description: 'Fed Rate End of 2026: Below 4%?',
          price: 0.55,
          resolutionTime: new Date('2026-12-08').getTime(),
          category: 'Economy',
          isLive: true,
        },
        {
          id: 'demo-6',
          description: 'SpaceX IPO via Ackman SPAR?',
          price: 0.30,
          resolutionTime: new Date('2026-12-31').getTime(),
          category: 'Technology',
          isLive: true,
        },
        {
          id: 'demo-7',
          description: 'AAPL Above $250 in April 2026?',
          price: 0.60,
          resolutionTime: new Date('2026-04-30').getTime(),
          category: 'Stocks',
          isLive: true,
        },
        {
          id: 'demo-8',
          description: 'OpenSea Token Launch by 2026?',
          price: 0.45,
          resolutionTime: new Date('2026-12-31').getTime(),
          category: 'Crypto',
          isLive: true,
        },
        {
          id: 'demo-9',
          description: 'Fed April 2026: Rate Cut?',
          price: 0.40,
          resolutionTime: new Date('2026-04-28').getTime(),
          category: 'Economy',
          isLive: true,
        },
        {
          id: 'demo-10',
          description: 'Argentina USD Rate Above 1500 ARS End of 2026?',
          price: 0.65,
          resolutionTime: new Date('2026-12-31').getTime(),
          category: 'Forex',
          isLive: true,
        },
      ]);
      setIsLoading(false);
      return;
    }

    // TODO: Implement actual contract reads when testnet deployment is funded
    // For now, use demo data with real market names from demo_markets.json
    setMarkets([
      {
        id: activeMarketIds[0] || 'demo-1',
        description: 'Largest IPO by Market Cap 2026: SpaceX?',
        price: 0.88,
        resolutionTime: new Date('2026-12-30').getTime(),
        category: 'Technology',
        isLive: true,
      },
      {
        id: activeMarketIds[1] || 'demo-2',
        description: 'US-Iran Ceasefire by April 30, 2026?',
        price: 0.35,
        resolutionTime: new Date('2026-04-30').getTime(),
        category: 'Geopolitics',
        isLive: true,
      },
    ]);
    setIsLoading(false);
  }, [activeMarketIds, loadingMarketIds]);

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
    };
    return colors[category] || colors['Other'];
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
          <p className="text-sm text-gray-600">
            Showing {markets.length} active markets
          </p>
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
                    <p className="text-gray-500">Current Price</p>
                    <p className={`font-semibold ${getPriceColor(market.price)}`}>
                      ${(market.price * 100).toFixed(1)}¢
                    </p>
                  </div>
                  <div>
                    <p className="text-gray-500">Probability</p>
                    <p className="font-semibold text-gray-900">
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
        <div className="text-center py-12">
          <p className="text-gray-500">Loading markets...</p>
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
