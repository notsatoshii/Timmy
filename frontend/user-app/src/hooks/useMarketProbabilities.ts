import { useState, useEffect, useCallback } from 'react';
import { useReadContract } from 'wagmi';
import { CONTRACT_ADDRESSES } from '../config/contracts';
import { ORACLE_ADAPTER_ABI } from '../config/abis';

// Demo market fallback data from scripts/oracle/demo_markets.json
const DEMO_MARKETS_FALLBACK = {
  "0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1": {
    name: "Largest IPO by Market Cap 2026: SpaceX?",
    category: "Technology",
    initial_probability: 0.6563,
    expiry: "2026-12-30T00:00:00Z"
  },
  "0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a": {
    name: "US-Iran Ceasefire by April 30, 2026?",
    category: "Geopolitics",
    initial_probability: 0.2882,
    expiry: "2026-04-30T00:00:00Z"
  },
  "0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d": {
    name: "Nothing Ever Happens: 2026",
    category: "Speculative",
    initial_probability: 0.3712,
    expiry: "2026-12-30T00:00:00Z"
  },
  "0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2": {
    name: "2026 FIFA World Cup Winner: Spain?",
    category: "Sports",
    initial_probability: 0.3758,
    expiry: "2026-07-19T00:00:00Z"
  },
  "0x14c648a4f4d0bc145e52ef68c38e29448c3f53a7856efe028b8b9282bb53ece7": {
    name: "Fed Rate End of 2026: Below 4%?",
    category: "Economy",
    initial_probability: 0.4371,
    expiry: "2026-12-08T00:00:00Z"
  },
  "0xc75c5438583a86308c965cee1a062f63b322bf00c9d47ccfc1c85b0b220111f2": {
    name: "SpaceX IPO via Ackman SPAR?",
    category: "Technology",
    initial_probability: 0.3189,
    expiry: "2026-12-31T00:00:00Z"
  },
  "0x9f22dfb07feaf97cf92a3dc91483a9ecb508f5815f331b4611a8d582e2dd4554": {
    name: "AAPL Above $250 in April 2026?",
    category: "Stocks",
    initial_probability: 0.6195,
    expiry: "2026-04-30T00:00:00Z"
  },
  "0x6dd2ecd673a166f34be2f101b96a048035bcfbcd0f98014491ca94449c159dbc": {
    name: "OpenSea Token Launch by 2026?",
    category: "Crypto",
    initial_probability: 0.4388,
    expiry: "2026-12-31T00:00:00Z"
  },
  "0xf715c6d9592ef93a01ff357bb5a3514c22ceeaa60e06223c0dcf75afad145e9f": {
    name: "Fed April 2026: Rate Cut?",
    category: "Economy",
    initial_probability: 0.4132,
    expiry: "2026-04-28T00:00:00Z"
  },
  "0xe73fd3dd7e069a651cfc9d63dae43702c320a661ab5c9dada3678994d18dffea": {
    name: "Argentina USD Rate Above 1500 ARS End of 2026?",
    category: "Forex",
    initial_probability: 0.5974,
    expiry: "2026-12-31T00:00:00Z"
  },
  "0x8215cf9d075f1ee6044f05d17fa1685d88da515f3ea119e10f50cb487f9e3774": {
    name: "BTC Above $80k March 2026?",
    category: "Crypto",
    initial_probability: 0.135,
    expiry: "2026-04-01T04:00:00Z"
  },
  "0x329ec977deb23dbc392959044918040f8a9252d502c6948eea33d2e72e787ddd": {
    name: "Masters 2026: Ludvig Aberg Wins?",
    category: "Sports",
    initial_probability: 0.059,
    expiry: "2026-04-13T00:00:00Z"
  },
  "0xc2a3fba66cdee6088484ae353b3c414390c591ac5cf485248f9b9cbb591a8cd4": {
    name: "Hungary PM: Viktor Orbán?",
    category: "Politics",
    initial_probability: 0.375,
    expiry: "2026-04-12T00:00:00Z"
  },
  "0x35f95cb4e4331813cbbcf8acd4efea29305a24ff890b4f22d163722095ebb706": {
    name: "Eurovision 2026: France Wins?",
    category: "Entertainment",
    initial_probability: 0.1255,
    expiry: "2026-05-16T00:00:00Z"
  },
  "0x73b37115e0a747b8fec07143017b8359a53677baa466a4847c6af7c14c0ec5c7": {
    name: "NCAA 2026: Florida Wins?",
    category: "Sports",
    initial_probability: 0.0925,
    expiry: "2026-04-04T00:00:00Z"
  },
  "0x6ee69274ed792087cd80dc1db0f90456f4d2621287375a0e90032f61bbe32e9e": {
    name: "Hungary Election: TISZA Most Seats?",
    category: "Politics",
    initial_probability: 0.655,
    expiry: "2026-04-12T00:00:00Z"
  },
  "0xdf341f72d47f0bbcb009aaa13d9d683a79ce8f77de068943c0316feade190c21": {
    name: "Fed April 2026: No Rate Change?",
    category: "Economy",
    initial_probability: 0.9465,
    expiry: "2026-04-29T00:00:00Z"
  },
  "0x0e6da084b18fb861b29203d611dc83df2bcfa3294281dd57ea735f3096023438": {
    name: "ETH Above $2600 March 2026?",
    category: "Crypto",
    initial_probability: 0.105,
    expiry: "2026-04-01T04:00:00Z"
  },
  "0x5131ef671dbddffe63e34798f3cf92be05c95001b20f29255f97d87b2d6e1de2": {
    name: "Iranian Regime Falls by April 30?",
    category: "Geopolitics",
    initial_probability: 0.115,
    expiry: "2026-04-30T00:00:00Z"
  },
  "0x7155116cef46226d9a58e096c87fba03555313c85b9b9b649dca754090845136": {
    name: "Trump Visits China by April 30?",
    category: "Geopolitics",
    initial_probability: 0.125,
    expiry: "2026-04-30T00:00:00Z"
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
  const { pollingInterval = 15000, enabled = true } = options;
  const [markets, setMarkets] = useState<MarketData[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [lastUpdate, setLastUpdate] = useState<number>(0);

  // State to track oracle probabilities — start null, show loading until first real fetch
  const [oracleProbabilities, setOracleProbabilities] = useState<Record<string, number> | null>(null);
  const [oracleError, setOracleError] = useState<string | null>(null);

  // Read PI for the first market to test oracle connectivity
  const { data: firstMarketPI, error: firstMarketError } = useReadContract({
    address: CONTRACT_ADDRESSES.oracleAdapter,
    abi: ORACLE_ADAPTER_ABI,
    functionName: 'getPI',
    args: [REAL_MARKET_IDS[0] as `0x${string}`],
    query: {
      enabled: enabled && !!CONTRACT_ADDRESSES.oracleAdapter,
      refetchInterval: pollingInterval,
      retry: false,
    }
  });

  // Function to fetch all market probabilities from OracleAdapter
  
  // Fetch from local prices.json (written by keeper, always available)
  const fetchLocalPrices = useCallback(async (): Promise<Record<string, number> | null> => {
    try {
      const response = await fetch('/prices.json?t=' + Date.now());
      if (!response.ok) return null;
      const data = await response.json();
      if (!data.prices || Date.now() / 1000 - data.lastUpdate > 120) return null; // stale > 2min
      const probabilities: Record<string, number> = {};
      for (const [marketId, info] of Object.entries(data.prices)) {
        probabilities[marketId] = (info as any).probability;
      }
      return probabilities;
    } catch {
      return null;
    }
  }, []);

  const fetchOracleProbabilities = useCallback(async (): Promise<Record<string, number> | null> => {
    if (!CONTRACT_ADDRESSES.oracleAdapter || firstMarketError) {
      return null;
    }

    try {
      // Use the readContract action for batch reading
      const { readContract } = await import('wagmi/actions');
      const { config } = await import('../config/wagmi');

      const probabilities: Record<string, number> = {};
      let successCount = 0;

      // Read PI for each market
      for (const marketId of REAL_MARKET_IDS) {
        try {
          const pi = await readContract(config, {
            address: CONTRACT_ADDRESSES.oracleAdapter,
            abi: ORACLE_ADAPTER_ABI,
            functionName: 'getPI',
            args: [marketId as `0x${string}`],
          });

          const piValue = Number(pi) / 1e18; // Convert from WAD to decimal

          // Sanity check: PI should be between 0 and 1
          if (piValue >= 0 && piValue <= 1) {
            probabilities[marketId] = piValue;
            successCount++;
          } else {
            console.warn(`Invalid PI value for market ${marketId}: ${piValue}`);
          }
        } catch (error) {
          console.warn(`Failed to read PI for market ${marketId}:`, error);
        }
      }

      if (successCount > 0) {
        console.log(`✓ Oracle read ${successCount}/${REAL_MARKET_IDS.length} markets successfully`);
        return probabilities;
      } else {
        console.warn('⚠ Oracle read 0 markets successfully, using fallback');
        return null;
      }
    } catch (error) {
      console.warn('Failed to read from OracleAdapter:', error);
      return null;
    }
  }, [firstMarketError]);

  // Effect to fetch oracle probabilities periodically
  useEffect(() => {
    if (!enabled || !CONTRACT_ADDRESSES.oracleAdapter) return;

    const updateOracleData = async () => {
      try {
        // Try local prices.json first (instant, no RPC needed)
        const localPrices = await fetchLocalPrices();
        if (localPrices && Object.keys(localPrices).length >= 8) {
          setOracleProbabilities(localPrices);
          setOracleError(null);
        } else {
          // Fallback to on-chain RPC
          const probabilities = await fetchOracleProbabilities();
          if (probabilities !== null) {
            setOracleProbabilities(probabilities);
            setOracleError(null);
          }
        }
        // If both fail, keep previous data
      } catch (error) {
        console.error('Error fetching oracle probabilities:', error);
        setOracleError(error instanceof Error ? error.message : 'Unknown error');
        // Keep last successful oracle data — never revert to hardcoded fallback
      }
    };

    // Initial fetch
    updateOracleData();

    // Set up polling interval
    const interval = setInterval(updateOracleData, pollingInterval);
    return () => clearInterval(interval);
  }, [enabled, pollingInterval, fetchOracleProbabilities]);

  // Effect to build market data from oracle + fallback
  useEffect(() => {
    if (!enabled) return;
    // Don't render with stale fallback — wait for first real fetch
    if (!oracleProbabilities) return;

    try {
      setIsLoading(false);

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
        console.log(`✓ Live Oracle Update: ${Object.keys(oracleProbabilities || {}).length} markets`);
      } else {
        console.log('ℹ Fallback to demo_markets.json data (oracle unavailable)');
      }

    } catch (error) {
      console.error('Error building market data:', error);

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
  }, [enabled, oracleProbabilities]);

  const refreshProbabilities = useCallback(() => {
    setLastUpdate(0); // Force refresh on next effect run
  }, []);

  return {
    markets,
    isLoading,
    lastUpdate,
    refreshProbabilities,
    hasOracleData: !!oracleProbabilities && Object.keys(oracleProbabilities).length > 0,
    oracleError
  };
};