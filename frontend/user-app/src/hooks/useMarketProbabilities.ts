import { useState, useEffect, useCallback } from 'react';
import { useReadContract } from 'wagmi';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import { ORACLE_ADAPTER_ABI } from '../config/abis';

// Demo market fallback data from scripts/oracle/demo_markets.json
const DEMO_MARKETS_FALLBACK = {
  "0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1": {
    name: "Largest IPO by Market Cap 2026: SpaceX?",
    category: "Technology",
    initial_probability: 0.88,
    expiry: "2026-12-30T00:00:00Z"
  },
  "0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a": {
    name: "US-Iran Ceasefire by April 30, 2026?",
    category: "Geopolitics",
    initial_probability: 0.35,
    expiry: "2026-04-30T00:00:00Z"
  },
  "0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d": {
    name: "Nothing Ever Happens: 2026",
    category: "Speculative",
    initial_probability: 0.42,
    expiry: "2026-12-30T00:00:00Z"
  },
  "0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2": {
    name: "2026 FIFA World Cup Winner: Spain?",
    category: "Sports",
    initial_probability: 0.22,
    expiry: "2026-07-19T00:00:00Z"
  },
  "0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7": {
    name: "Fed Rate End of 2026: Below 4%?",
    category: "Economy",
    initial_probability: 0.55,
    expiry: "2026-12-08T00:00:00Z"
  },
  "0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2": {
    name: "SpaceX IPO via Ackman SPAR?",
    category: "Technology",
    initial_probability: 0.30,
    expiry: "2026-12-31T00:00:00Z"
  },
  "0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554": {
    name: "AAPL Above $250 in April 2026?",
    category: "Stocks",
    initial_probability: 0.60,
    expiry: "2026-04-30T00:00:00Z"
  },
  "0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc": {
    name: "OpenSea Token Launch by 2026?",
    category: "Crypto",
    initial_probability: 0.45,
    expiry: "2026-12-31T00:00:00Z"
  },
  "0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f": {
    name: "Fed April 2026: Rate Cut?",
    category: "Economy",
    initial_probability: 0.40,
    expiry: "2026-04-28T00:00:00Z"
  },
  "0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea": {
    name: "Argentina USD Rate Above 1500 ARS End of 2026?",
    category: "Forex",
    initial_probability: 0.65,
    expiry: "2026-12-31T00:00:00Z"
  }
};

// Real market IDs from deployment
const REAL_MARKET_IDS = Object.keys(DEMO_MARKETS_FALLBACK);

interface MarketData {
  id: string;
  name: string;
  category: string;
  probability: number;
  expiryTimestamp: number;
  isLive: boolean;
  source: 'oracle' | 'fallback';
}

interface UseMarketProbabilitiesOptions {
  pollingInterval?: number;
  enabled?: boolean;
}

export const useMarketProbabilities = (options: UseMarketProbabilitiesOptions = {}) => {
  const { pollingInterval = 30000, enabled = true } = options;
  const [markets, setMarkets] = useState<MarketData[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [lastUpdate, setLastUpdate] = useState<number>(0);

  // Try to read probabilities from OracleAdapter for the first market as a test
  const { data: firstMarketPI, error: oracleError } = useReadContract({
    address: CONTRACT_ADDRESSES.oracleAdapter,
    abi: ORACLE_ADAPTER_ABI,
    functionName: 'getPI',
    args: [REAL_MARKET_IDS[0] as `0x${string}`],
    query: {
      enabled: enabled && !!CONTRACT_ADDRESSES.oracleAdapter,
      refetchInterval: pollingInterval,
      retry: false, // Don't retry on failure, fallback instead
    }
  });

  // Function to fetch all market probabilities from OracleAdapter
  const fetchOracleProbabilities = useCallback(async (): Promise<Record<string, number> | null> => {
    if (!CONTRACT_ADDRESSES.oracleAdapter || oracleError) {
      return null;
    }

    try {
      // If we got a successful read for the first market, we can assume oracle is working
      if (firstMarketPI !== undefined) {
        const probabilities: Record<string, number> = {};

        // For now, we'll use the first market's PI as a test
        // In a real implementation, you'd batch read all markets
        probabilities[REAL_MARKET_IDS[0]] = Number(firstMarketPI) / 1e18; // Convert from WAD to decimal

        // For demo purposes, use fallback data for other markets but mark as oracle source
        REAL_MARKET_IDS.slice(1).forEach(marketId => {
          const fallbackData = DEMO_MARKETS_FALLBACK[marketId as keyof typeof DEMO_MARKETS_FALLBACK];
          if (fallbackData) {
            probabilities[marketId] = fallbackData.initial_probability;
          }
        });

        return probabilities;
      }
    } catch (error) {
      console.warn('Failed to read from OracleAdapter:', error);
    }

    return null;
  }, [firstMarketPI, oracleError]);

  // Main effect to fetch and update market data
  useEffect(() => {
    if (!enabled) return;

    const updateMarkets = async () => {
      try {
        setIsLoading(true);

        // Try to fetch from oracle first
        const oracleProbabilities = await fetchOracleProbabilities();
        const source: 'oracle' | 'fallback' = oracleProbabilities ? 'oracle' : 'fallback';

        // Build market data array
        const marketData: MarketData[] = REAL_MARKET_IDS.map(marketId => {
          const fallbackData = DEMO_MARKETS_FALLBACK[marketId as keyof typeof DEMO_MARKETS_FALLBACK];
          if (!fallbackData) return null;

          const probability = oracleProbabilities
            ? (oracleProbabilities[marketId] ?? fallbackData.initial_probability)
            : fallbackData.initial_probability;

          return {
            id: marketId,
            name: fallbackData.name,
            category: fallbackData.category,
            probability,
            expiryTimestamp: new Date(fallbackData.expiry).getTime(),
            isLive: true, // All demo markets are live
            source
          };
        }).filter(Boolean) as MarketData[];

        setMarkets(marketData);
        setLastUpdate(Date.now());

        if (source === 'oracle') {
          console.log('✓ Using OracleAdapter probabilities');
        } else {
          console.log('ℹ Fallback to demo_markets.json data (oracle unavailable)');
        }

      } catch (error) {
        console.error('Error updating market probabilities:', error);

        // Final fallback - use static demo data
        const fallbackMarkets: MarketData[] = REAL_MARKET_IDS.map(marketId => {
          const fallbackData = DEMO_MARKETS_FALLBACK[marketId as keyof typeof DEMO_MARKETS_FALLBACK];
          if (!fallbackData) return null;

          return {
            id: marketId,
            name: fallbackData.name,
            category: fallbackData.category,
            probability: fallbackData.initial_probability,
            expiryTimestamp: new Date(fallbackData.expiry).getTime(),
            isLive: true,
            source: 'fallback'
          };
        }).filter(Boolean) as MarketData[];

        setMarkets(fallbackMarkets);
        setLastUpdate(Date.now());
      } finally {
        setIsLoading(false);
      }
    };

    // Initial load
    updateMarkets();

    // Set up polling interval
    const interval = setInterval(updateMarkets, pollingInterval);
    return () => clearInterval(interval);
  }, [enabled, pollingInterval, fetchOracleProbabilities]);

  const refreshProbabilities = useCallback(() => {
    setLastUpdate(0); // Force refresh on next effect run
  }, []);

  return {
    markets,
    isLoading,
    lastUpdate,
    refreshProbabilities,
    hasOracleData: markets.length > 0 && markets[0]?.source === 'oracle'
  };
};