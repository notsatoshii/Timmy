import { useState, useEffect, useCallback, useRef } from 'react';
import { useReadContract } from 'wagmi';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import { ORACLE_ADAPTER_ABI } from '../config/abis';

interface LivePrice {
  marketId: string;
  pi: number; // Probability Index (0-1)
  lastUpdated: number;
}

interface UseLivePricesOptions {
  marketIds: string[];
  pollingInterval?: number; // in milliseconds, default 30 seconds
  enabled?: boolean;
}

export const useLivePrices = (options: UseLivePricesOptions) => {
  const { marketIds, pollingInterval = 30000, enabled = true } = options;
  const [prices, setPrices] = useState<Record<string, LivePrice>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [lastUpdate, setLastUpdate] = useState<number>(0);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  // Fetch a single market's price
  const fetchMarketPrice = useCallback(async (marketId: string) => {
    try {
      // For now, we'll simulate price updates since we're using demo data
      // In production, this would call the actual contract read
      const currentPrice = prices[marketId]?.pi || 0.5;

      // Simulate small random price movements (±2%)
      const volatility = 0.02;
      const randomChange = (Math.random() - 0.5) * 2 * volatility;
      let newPrice = currentPrice + randomChange;

      // Keep price within bounds [0.01, 0.99]
      newPrice = Math.max(0.01, Math.min(0.99, newPrice));

      return {
        marketId,
        pi: newPrice,
        lastUpdated: Date.now(),
      };
    } catch (error) {
      console.warn(`Failed to fetch price for market ${marketId}:`, error);
      return null;
    }
  }, [prices]);

  // Fetch all market prices
  const fetchAllPrices = useCallback(async () => {
    if (!enabled || marketIds.length === 0) return;

    try {
      const pricePromises = marketIds.map(marketId => fetchMarketPrice(marketId));
      const results = await Promise.all(pricePromises);

      const newPrices: Record<string, LivePrice> = {};
      results.forEach(result => {
        if (result) {
          newPrices[result.marketId] = result;
        }
      });

      setPrices(prev => ({ ...prev, ...newPrices }));
      setLastUpdate(Date.now());
      setIsLoading(false);
    } catch (error) {
      console.error('Failed to fetch market prices:', error);
      setIsLoading(false);
    }
  }, [enabled, marketIds, fetchMarketPrice]);

  // Initialize prices with demo data
  useEffect(() => {
    if (marketIds.length > 0 && Object.keys(prices).length === 0) {
      const initialPrices: Record<string, LivePrice> = {};

      // Demo market initial prices matching the Markets component
      const demoInitialPrices = {
        'demo-1': 0.88, // SpaceX IPO
        'demo-2': 0.35, // US-Iran Ceasefire
        'demo-3': 0.42, // Nothing Ever Happens
        'demo-4': 0.22, // FIFA World Cup Spain
        'demo-5': 0.55, // Fed Rate Below 4%
        'demo-6': 0.30, // SpaceX SPAR IPO
        'demo-7': 0.60, // AAPL $250
        'demo-8': 0.45, // OpenSea Token
        'demo-9': 0.40, // Fed Rate Cut April
        'demo-10': 0.65, // Argentina USD Rate
      };

      marketIds.forEach(marketId => {
        initialPrices[marketId] = {
          marketId,
          pi: demoInitialPrices[marketId as keyof typeof demoInitialPrices] || 0.5,
          lastUpdated: Date.now(),
        };
      });

      setPrices(initialPrices);
      setIsLoading(false);
    }
  }, [marketIds, prices]);

  // Set up polling
  useEffect(() => {
    if (!enabled || marketIds.length === 0) return;

    // Initial fetch
    fetchAllPrices();

    // Set up polling interval
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
    }

    intervalRef.current = setInterval(fetchAllPrices, pollingInterval);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [enabled, marketIds, pollingInterval, fetchAllPrices]);

  // Manual refresh function
  const refreshPrices = useCallback(() => {
    fetchAllPrices();
  }, [fetchAllPrices]);

  return {
    prices,
    isLoading,
    lastUpdate,
    refreshPrices,
  };
};

// Helper hook for a single market price
export const useLivePrice = (marketId: string, pollingInterval?: number) => {
  const { prices, isLoading, lastUpdate, refreshPrices } = useLivePrices({
    marketIds: [marketId],
    pollingInterval,
  });

  return {
    price: prices[marketId] || null,
    isLoading,
    lastUpdate,
    refreshPrice: refreshPrices,
  };
};