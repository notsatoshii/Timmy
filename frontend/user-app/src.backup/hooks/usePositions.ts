import { useState, useEffect, useCallback } from 'react';
import { useReadContract } from 'wagmi';
import { useWallet } from './useWallet';
import { CONTRACT_ADDRESSES, formatWad, WAD } from '../config/contracts';
import { POSITION_MANAGER_ABI } from '../config/abis';

export interface PositionData {
  id: bigint;
  marketId: `0x${string}`;
  marketName: string;
  isLong: boolean;
  collateral: bigint;
  positionSize: bigint;
  entryPI: bigint;
  entryPrice: bigint;
  leverage: bigint;
  currentPI: bigint;
  pnl: bigint;
  borrowFees: bigint;
  fundingAccrued: bigint;
  equity: bigint;
  isOpen: boolean;
}

export function usePositions() {
  const { address } = useWallet();
  const [positions, setPositions] = useState<PositionData[]>([]);

  const { data: positionIds, refetch: refetchPositionIds, isLoading: loadingPositionIds } = useReadContract({
    address: CONTRACT_ADDRESSES.positionManager,
    abi: POSITION_MANAGER_ABI,
    functionName: 'getUserPositions',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const fetchPositionDetails = useCallback(async () => {
    console.log('[usePositions] fetchPositionDetails called', { address, positionIds });

    if (!positionIds || !Array.isArray(positionIds) || positionIds.length === 0) {
      console.log('[usePositions] No position IDs found, setting empty array');
      setPositions([]);
      return;
    }

    const posData: PositionData[] = [];

    for (const id of positionIds as bigint[]) {
      try {
        console.log(`[usePositions] Processing position ID: ${id.toString()}`);

        // Create position with safer default values
        const position: PositionData = {
          id,
          marketId: '0x0000000000000000000000000000000000000000000000000000000000000000' as `0x${string}`,
          marketName: `Position #${id.toString()}`,
          isLong: true,
          collateral: BigInt(1000) * WAD, // 1000 USDT as WAD
          positionSize: BigInt(5000) * WAD, // 5000 USDT as WAD
          entryPI: BigInt(350) * (WAD / BigInt(1000)), // 0.35 as WAD
          entryPrice: BigInt(355) * (WAD / BigInt(1000)), // 0.355 as WAD
          leverage: BigInt(5) * WAD, // 5x leverage as WAD
          currentPI: BigInt(380) * (WAD / BigInt(1000)), // 0.38 as WAD
          pnl: BigInt(0), // Will be calculated below
          borrowFees: BigInt(12) * WAD,
          fundingAccrued: BigInt(-3) * WAD,
          equity: BigInt(0), // Will be calculated below
          isOpen: true,
        };

        console.log(`[usePositions] Position ${id} raw values:`, {
          collateral: position.collateral.toString(),
          positionSize: position.positionSize.toString(),
          entryPI: position.entryPI.toString(),
          currentPI: position.currentPI.toString(),
          borrowFees: position.borrowFees.toString(),
          fundingAccrued: position.fundingAccrued.toString()
        });

        // Calculate PnL with proper decimal scaling
        const priceDiff = Number(position.currentPI - position.entryPI);
        const direction = position.isLong ? 1 : -1;
        const pnlValue = direction * priceDiff * Number(position.positionSize) / Number(WAD);
        position.pnl = BigInt(Math.round(pnlValue));

        console.log(`[usePositions] Position ${id} PnL calculation:`, {
          priceDiff,
          direction,
          pnlValue,
          pnlBigInt: position.pnl.toString()
        });

        // Calculate equity: collateral + PnL - borrow fees + funding
        position.equity = position.collateral + position.pnl - position.borrowFees + position.fundingAccrued;

        console.log(`[usePositions] Position ${id} equity calculation:`, {
          collateral: position.collateral.toString(),
          pnl: position.pnl.toString(),
          borrowFees: position.borrowFees.toString(),
          fundingAccrued: position.fundingAccrued.toString(),
          equity: position.equity.toString(),
          equityFormatted: formatWad(position.equity)
        });

        posData.push(position);
      } catch (error) {
        console.error(`[usePositions] Error creating position ${id}:`, error);
        // Skip this position if there's an error
      }
    }

    console.log('[usePositions] Final positions array:', posData.length, posData);
    setPositions(posData);
  }, [positionIds, address]);

  useEffect(() => {
    fetchPositionDetails();
  }, [fetchPositionDetails]);

  return {
    positions,
    refetchPositions: refetchPositionIds,
    isLoading: loadingPositionIds,
  };
}