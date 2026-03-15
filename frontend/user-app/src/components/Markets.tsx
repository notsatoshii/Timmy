import React, { useState, useEffect, useMemo } from 'react';
import { useReadContract } from 'wagmi';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import { MARKET_REGISTRY_ABI } from '../config/abis';

interface Market {
  id: string;
  description: string;
  price: number;
  resolutionTime: number;
  category: string;
  isLive: boolean;
}

const Markets: React.FC = () => {
  const [markets, setMarkets] = useState<Market[]>([]);

  // Read active markets from MarketRegistry
  const { data: activeMarketIds } = useReadContract({
    address: CONTRACT_ADDRESSES.marketRegistry,
    abi: MARKET_REGISTRY_ABI,
    functionName: 'getActiveMarkets',
  });

  // Mock data for demonstration (since we might not have markets deployed yet)
  const mockMarkets: Market[] = useMemo(() => [
    {
      id: '0x1',
      description: 'Bitcoin will reach $100,000 by end of March 2026',
      price: 0.65,
      resolutionTime: new Date('2026-03-31').getTime(),
      category: 'Crypto',
      isLive: true,
    },
    {
      id: '0x2',
      description: 'US Presidential Election 2028 - Democratic Party Win',
      price: 0.48,
      resolutionTime: new Date('2028-11-15').getTime(),
      category: 'Politics',
      isLive: true,
    },
    {
      id: '0x3',
      description: 'AI will solve protein folding by 2027',
      price: 0.72,
      resolutionTime: new Date('2027-12-31').getTime(),
      category: 'Technology',
      isLive: true,
    },
    {
      id: '0x4',
      description: 'Next Super Bowl winner will be AFC team',
      price: 0.52,
      resolutionTime: new Date('2026-02-15').getTime(),
      category: 'Sports',
      isLive: true,
    },
  ], []);

  useEffect(() => {
    // Use mock data for now
    setMarkets(mockMarkets);
  }, [activeMarketIds, mockMarkets]);

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
                  <button className="bg-success-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-success-700 transition-colors">
                    Long
                  </button>
                  <button className="bg-danger-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-danger-700 transition-colors">
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

      {markets.length === 0 && (
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
