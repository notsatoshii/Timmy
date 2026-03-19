import { useState, useEffect } from 'react';
import { usePublicClient } from 'wagmi';
import { getContractAddresses } from '../config/contracts';

const DEPLOYMENT_BLOCK = BigInt(39050000);

export const useVolumeCalculation = (enabled: boolean = true) => {
  const [volume24h, setVolume24h] = useState<bigint>(BigInt(0));
  const [isLoading, setIsLoading] = useState(true);
  const publicClient = usePublicClient();

  useEffect(() => {
    if (!enabled || !publicClient) return;

    const calculateVolume = async () => {
      try {
        setIsLoading(true);
        const addresses = getContractAddresses();
        const currentBlock = await publicClient.getBlockNumber();
        let totalVolume = BigInt(0);
        const batchSize = BigInt(5000);
        let from = DEPLOYMENT_BLOCK;

        while (from < currentBlock) {
          const to = from + batchSize > currentBlock ? currentBlock : from + batchSize;
          try {
            const logs = await publicClient.getLogs({
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
                  { name: 'positionSize', type: 'uint256', indexed: false },
                ],
              },
              fromBlock: from,
              toBlock: to,
            });

            for (const log of logs) {
              if (log.args && log.args.positionSize) {
                totalVolume += BigInt(log.args.positionSize);
              }
            }
          } catch (e) {
            console.warn('Volume batch error:', from.toString(), e);
          }
          from = to + BigInt(1);
        }

        setVolume24h(totalVolume);
      } catch (err) {
        console.error('Error calculating volume:', err);
        setVolume24h(BigInt(0));
      } finally {
        setIsLoading(false);
      }
    };

    calculateVolume();
  }, [enabled, publicClient]);

  return { volume24h, isLoading, error: null };
};
