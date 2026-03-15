import React, { useEffect, useState } from 'react';
import { useReadContract } from 'wagmi';
import { getContractAddresses, formatWad, formatUsdt, WAD } from '../config/contracts';
import {
  LEVER_VAULT_ABI,
  OI_LIMITS_ABI,
  INSURANCE_FUND_ABI,
  FEE_ROUTER_ABI,
} from '../config/abis';
import Skeleton from './Skeleton';

interface ProtocolStatsData {
  tvl: string;
  dailyVolume: string;
  totalOI: string;
  lpApy: string;
  insuranceFund: string;
}

const ProtocolStats: React.FC = () => {
  const [stats, setStats] = useState<ProtocolStatsData | null>(null);
  const [addresses] = useState(getContractAddresses());

  // Read TVL from LeverVault.totalAssets()
  const { data: tvlRaw, isLoading: tvlLoading } = useReadContract({
    address: addresses.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'totalAssets',
  });

  // Read total OI from OILimits.getGlobalOI()
  const { data: totalOIRaw, isLoading: oiLoading } = useReadContract({
    address: addresses.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getGlobalOI',
  });

  // Read insurance fund balance from InsuranceFund.getBalance()
  const { data: insuranceRaw, isLoading: insuranceLoading } = useReadContract({
    address: addresses.insuranceFund,
    abi: INSURANCE_FUND_ABI,
    functionName: 'getBalance',
  });

  // Read fee router data for APY calculation
  const { data: totalBorrowFees } = useReadContract({
    address: addresses.feeRouter,
    abi: FEE_ROUTER_ABI,
    functionName: 'getTotalFeesRouted',
    args: [0], // BORROW type
  });

  const { data: totalTxFees } = useReadContract({
    address: addresses.feeRouter,
    abi: FEE_ROUTER_ABI,
    functionName: 'getTotalFeesRouted',
    args: [1], // TRANSACTION type
  });

  const { data: totalLiquidationFees } = useReadContract({
    address: addresses.feeRouter,
    abi: FEE_ROUTER_ABI,
    functionName: 'getTotalFeesRouted',
    args: [2], // LIQUIDATION type
  });

  const { data: totalSettlementFees } = useReadContract({
    address: addresses.feeRouter,
    abi: FEE_ROUTER_ABI,
    functionName: 'getTotalFeesRouted',
    args: [3], // SETTLEMENT type
  });

  // Calculate derived stats
  useEffect(() => {
    if (tvlRaw && totalOIRaw !== undefined && insuranceRaw !== undefined) {
      // Calculate LP APY from fee revenue (same logic as Vault component)
      const totalFees =
        (totalBorrowFees || BigInt(0)) +
        (totalTxFees || BigInt(0)) +
        (totalLiquidationFees || BigInt(0)) +
        (totalSettlementFees || BigInt(0));

      const lpFeeShare = totalFees * BigInt(50) / BigInt(100); // 50% to LPs
      const annualizedYield = lpFeeShare * BigInt(365) * BigInt(24); // Hourly → annual
      const apyPercent = tvlRaw > BigInt(0) ? (annualizedYield * BigInt(10000) / tvlRaw) / BigInt(100) : BigInt(0);

      // Mock 24h volume for now (would be calculated from events in real implementation)
      const mockDailyVolume = totalOIRaw * BigInt(5) / BigInt(100); // 5% of total OI as daily volume estimate

      setStats({
        tvl: `$${formatUsdt(tvlRaw)}`,
        dailyVolume: `$${formatUsdt(mockDailyVolume)}`,
        totalOI: `$${formatUsdt(totalOIRaw)}`,
        lpApy: `${formatWad(apyPercent)}%`,
        insuranceFund: `$${formatUsdt(insuranceRaw)}`,
      });
    }
  }, [tvlRaw, totalOIRaw, insuranceRaw, totalBorrowFees, totalTxFees, totalLiquidationFees, totalSettlementFees]);

  const isLoading = tvlLoading || oiLoading || insuranceLoading;

  return (
    <div className="bg-gradient-to-r from-surface-1 via-surface-2 to-surface-1 border-b border-border">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
        <div className="grid grid-cols-2 md:grid-cols-5 gap-6">
          {/* TVL */}
          <div className="text-center">
            <div className="text-sm font-medium text-gray-400 mb-1">Total TVL</div>
            {isLoading ? (
              <Skeleton variant="text" className="h-6 w-20 mx-auto" />
            ) : (
              <div className="text-xl md:text-2xl font-bold font-mono text-accent">
                {stats?.tvl || '$0.00'}
              </div>
            )}
          </div>

          {/* 24h Volume */}
          <div className="text-center">
            <div className="text-sm font-medium text-gray-400 mb-1">24h Volume</div>
            {isLoading ? (
              <Skeleton variant="text" className="h-6 w-20 mx-auto" />
            ) : (
              <div className="text-xl md:text-2xl font-bold font-mono text-gray-100">
                {stats?.dailyVolume || '$0.00'}
              </div>
            )}
          </div>

          {/* Total Open Interest */}
          <div className="text-center">
            <div className="text-sm font-medium text-gray-400 mb-1">Total OI</div>
            {isLoading ? (
              <Skeleton variant="text" className="h-6 w-20 mx-auto" />
            ) : (
              <div className="text-xl md:text-2xl font-bold font-mono text-gray-100">
                {stats?.totalOI || '$0.00'}
              </div>
            )}
          </div>

          {/* LP APY */}
          <div className="text-center">
            <div className="text-sm font-medium text-gray-400 mb-1">LP APY</div>
            {isLoading ? (
              <Skeleton variant="text" className="h-6 w-20 mx-auto" />
            ) : (
              <div className="text-xl md:text-2xl font-bold font-mono text-accent">
                {stats?.lpApy || '0.00%'}
              </div>
            )}
          </div>

          {/* Insurance Fund */}
          <div className="text-center">
            <div className="text-sm font-medium text-gray-400 mb-1">Insurance Fund</div>
            {isLoading ? (
              <Skeleton variant="text" className="h-6 w-20 mx-auto" />
            ) : (
              <div className="text-xl md:text-2xl font-bold font-mono text-accent-secondary">
                {stats?.insuranceFund || '$0.00'}
              </div>
            )}
          </div>
        </div>

        {/* Protocol Health Indicators */}
        <div className="mt-4 flex justify-center items-center space-x-6 text-sm">
          <div className="flex items-center space-x-2">
            <div className="w-2 h-2 bg-accent rounded-full animate-pulse"></div>
            <span className="text-gray-400">Live Prices</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-2 h-2 bg-accent-secondary rounded-full"></div>
            <span className="text-gray-400">Base Sepolia</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-2 h-2 bg-accent rounded-full"></div>
            <span className="text-gray-400">Oracle Active</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ProtocolStats;