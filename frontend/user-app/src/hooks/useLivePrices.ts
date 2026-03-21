import { useState, useEffect, useCallback, useRef } from 'react';

interface LivePrice {
  marketId: string;
  pi: number;
  lastUpdated: number;
}

interface UseLivePricesOptions {
  marketIds: string[];
  pollingInterval?: number;
  enabled?: boolean;
}


export const useLivePrices = (options: UseLivePricesOptions) => {
  const { marketIds, pollingInterval = 30000, enabled = true } = options;
  const [prices, setPrices] = useState<Record<string, LivePrice>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [lastUpdate, setLastUpdate] = useState<number>(0);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  // Ref to read current prices without creating callback dependency
  const pricesRef = useRef(prices);
  pricesRef.current = prices;

  // Stable market IDs string for dependency comparison
  const marketIdsKey = marketIds.join(',');

  // Initialize prices once
  useEffect(() => {
    const initialPrices: Record<string, LivePrice> = {};
    marketIds.forEach(marketId => {
      initialPrices[marketId] = {
        marketId,
        pi: 0.5,
        lastUpdated: Date.now(),
      };
    });
    setPrices(initialPrices);
    setIsLoading(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [marketIdsKey]);

  // Simulate price movements — reads from ref, no circular dep
  const simulatePriceUpdate = useCallback(() => {
    const current = pricesRef.current;
    const updated: Record<string, LivePrice> = {};

    marketIds.forEach(marketId => {
      const currentPrice = current[marketId]?.pi || 0.5;
      const volatility = 0.02;
      const randomChange = (Math.random() - 0.5) * 2 * volatility;
      const newPrice = Math.max(0.01, Math.min(0.99, currentPrice + randomChange));

      updated[marketId] = {
        marketId,
        pi: newPrice,
        lastUpdated: Date.now(),
      };
    });

    setPrices(prev => ({ ...prev, ...updated }));
    setLastUpdate(Date.now());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [marketIdsKey]);

  // Polling on a stable interval — no dependency on prices
  useEffect(() => {
    if (!enabled || marketIds.length === 0) return;

    if (intervalRef.current) {
      clearInterval(intervalRef.current);
    }

    intervalRef.current = setInterval(simulatePriceUpdate, pollingInterval);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, marketIdsKey, pollingInterval, simulatePriceUpdate]);

  const refreshPrices = useCallback(() => {
    simulatePriceUpdate();
  }, [simulatePriceUpdate]);

  return {
    prices,
    isLoading,
    lastUpdate,
    refreshPrices,
  };
};

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
