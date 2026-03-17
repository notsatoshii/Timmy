import { useState, useEffect } from 'react';
import { usePublicClient } from 'wagmi';
import { getContractAddresses } from '../config/contracts';
import { EXECUTION_ENGINE_ABI } from '../config/abis';

export const useVolumeCalculation = (enabled: boolean = true) => {
  const [volume24h, setVolume24h] = useState<bigint>(BigInt(0));
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const publicClient = usePublicClient();

  useEffect(() => {
    if (!enabled || !publicClient) return;

    const calculate24hVolume = async () => {
      try {
        setIsLoading(true);
        setError(null);

        // Get current block number
        const currentBlock = await publicClient.getBlockNumber();

        // Estimate blocks for last 24 hours on Base (2 second block time)
        const blocksIn24h = BigInt(24 * 60 * 60 / 2); // 43,200 blocks
        const fromBlock = currentBlock > blocksIn24h ? currentBlock - blocksIn24h : BigInt(0);

        const addresses = getContractAddresses();

        // Fetch PositionOpened events from last 24h
        const positionOpenedEvents = await publicClient.getLogs({
          address: addresses.executionEngine,
          event: {
            type: 'event',
            name: 'PositionOpened',
            inputs: [
              { name: 'positionId', type: 'uint256', indexed: true },
              { name: 'marketId', type: 'bytes32', indexed: true },
              { name: 'owner', type: 'address', indexed: true },
              { name: 'isLong', type: 'bool', indexed: false },
              { name: 'collateral', type: 'uint256', indexed: false },
              { name: 'leverage', type: 'uint256', indexed: false },
              { name: 'entryPI', type: 'uint256', indexed: false },
              { name: 'entryPrice', type: 'uint256', indexed: false },
              { name: 'positionSize', type: 'uint256', indexed: false },
              { name: 'impact', type: 'uint256', indexed: false },
              { name: 'timestamp', type: 'uint256', indexed: false },
            ]
          },
          fromBlock,
          toBlock: currentBlock,
        });

        // Calculate notional volume: sum of positionSize (which IS the notional) for all trades
        let totalNotionalVolume = BigInt(0);

        for (const event of positionOpenedEvents) {
          if (event.args && event.args.positionSize) {
            // Use the actual positionSize from the event (which is the notional value)
            const notionalValue = BigInt(event.args.positionSize);
            totalNotionalVolume += notionalValue;
          }
        }

        setVolume24h(totalNotionalVolume);

      } catch (err) {
        console.error('Error calculating 24h volume:', err);

        // Fallback to mock calculation if event fetching fails
        // For now, we'll use the existing mock data from trade history
        // This provides realistic demo data while event infrastructure is being established
        const mockVolume24h = BigInt('12800000000'); // Sum of mock trade notionals: 8000 + 4800 = 12800 USDT (already notional, not just collateral)
        setVolume24h(mockVolume24h);

        setError('Using demo volume data - live event tracking pending');
      } finally {
        setIsLoading(false);
      }
    };

    calculate24hVolume();

    // Refresh every 5 minutes
    const interval = setInterval(calculate24hVolume, 5 * 60 * 1000);

    return () => clearInterval(interval);
  }, [enabled, publicClient]);

  return {
    volume24h,
    isLoading,
    error,
  };
};