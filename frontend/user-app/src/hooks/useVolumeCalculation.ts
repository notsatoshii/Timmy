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

        // Fetch all historical events from block 0
        const fromBlock = currentBlock > BigInt(10000) ? currentBlock - BigInt(10000) : BigInt(0);

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

        // Set volume to zero when no events found
        setVolume24h(BigInt(0));

        setError('No volume events found - showing zero');
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