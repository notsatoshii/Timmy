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
  const { marketIds, pollingInterval = 15000, enabled = true } = options;
  const [prices, setPrices] = useState<Record<string, LivePrice>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [lastUpdate, setLastUpdate] = useState<number>(0);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const marketIdsKey = marketIds.join(',');

  const fetchPrices = useCallback(async () => {
    try {
      const response = await fetch('/prices.json?t=' + Date.now());
      if (!response.ok) return;

      const data = await response.json();
      const pricesData = data.prices || data;
      const updated: Record<string, LivePrice> = {};

      marketIds.forEach(marketId => {
        const entry = pricesData[marketId];
        if (entry && typeof entry.probability === 'number') {
          updated[marketId] = {
            marketId,
            pi: entry.probability,
            lastUpdated: (entry.timestamp || data.lastUpdate || 0) * 1000,
          };
        } else {
          // Keep existing price or use 0.5 default
          updated[marketId] = {
            marketId,
            pi: prices[marketId]?.pi || 0.5,
            lastUpdated: Date.now(),
          };
        }
      });

      setPrices(prev => ({ ...prev, ...updated }));
      setLastUpdate(Date.now());
      setIsLoading(false);
    } catch (e) {
      console.warn('Failed to fetch prices.json:', e);
      setIsLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [marketIdsKey]);

  // Initial fetch
  useEffect(() => {
    if (!enabled || marketIds.length === 0) return;
    fetchPrices();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, marketIdsKey]);

  // Polling
  useEffect(() => {
    if (!enabled || marketIds.length === 0) return;

    if (intervalRef.current) {
      clearInterval(intervalRef.current);
    }

    intervalRef.current = setInterval(fetchPrices, pollingInterval);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, marketIdsKey, pollingInterval, fetchPrices]);

  return {
    prices,
    isLoading,
    lastUpdate,
    refreshPrices: fetchPrices,
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
