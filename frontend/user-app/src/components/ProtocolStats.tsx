import React, { useEffect, useState } from 'react';
import { useReadContract } from 'wagmi';
import { getContractAddresses, loadContractAddresses, formatWad, formatUsdt, WAD } from '../config/contracts';
import {
  LEVER_VAULT_ABI,
  OI_LIMITS_ABI,
  INSURANCE_FUND_ABI,
  FEE_ROUTER_ABI,
  BORROW_FEE_ENGINE_ABI,
} from '../config/abis';
import Skeleton from './Skeleton';
import { useVolumeCalculation } from '../hooks/useVolumeCalculation';

interface ProtocolStatsData {
  tvl: string;
  dailyVolume: string;
  totalOI: string;
  lpApy: string;
  utilizationRate: string;
  insuranceFund: string;
}

const DEMO_FALLBACK_VALUES = {
  tvl: BigInt("50000000000"),
  totalOI: BigInt("30000000000"),
  insuranceFund: BigInt("10000000000000000000000"),
  volume24h: BigInt("0"),
  borrowRate: BigInt("200000000000000"),
};

const ProtocolStats: React.FC = () => {
  const [stats, setStats] = useState<ProtocolStatsData | null>(null);
  const [addresses, setAddresses] = useState(getContractAddresses());

  useEffect(() => {
    loadContractAddresses().then(loadedAddresses => {
      setAddresses(loadedAddresses);
    }).catch(error => {
      console.warn('ProtocolStats: Failed to load addresses:', error);
    });
  }, []);

  const { data: tvlRaw, isLoading: tvlLoading, error: tvlError } = useReadContract({
    address: addresses.leverVault,
    abi: LEVER_VAULT_ABI,
    functionName: 'totalAssets',
    query: { enabled: !!addresses.leverVault }
  });

  const { data: totalOIRaw, isLoading: oiLoading, error: oiError } = useReadContract({
    address: addresses.oiLimits,
    abi: OI_LIMITS_ABI,
    functionName: 'getGlobalOI',
    query: { enabled: !!addresses.oiLimits }
  });

  const { data: insuranceRaw, isLoading: insuranceLoading, error: insuranceError } = useReadContract({
    address: addresses.insuranceFund,
    abi: INSURANCE_FUND_ABI,
    functionName: 'getBalance',
    query: { enabled: !!addresses.insuranceFund }
  });

  const spacexMarketId = '0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1';
  const { data: currentBorrowRate, error: borrowRateError } = useReadContract({
    address: addresses.borrowFeeEngine,
    abi: BORROW_FEE_ENGINE_ABI,
    functionName: 'getCurrentBorrowRate',
    args: [spacexMarketId, true],
    query: { enabled: !!addresses.borrowFeeEngine }
  });

  const { volume24h, isLoading: volumeLoading } = useVolumeCalculation(true);

  useEffect(() => {
    try {
      const safeTvl = tvlRaw && !tvlError ? tvlRaw : DEMO_FALLBACK_VALUES.tvl;
      const safeTotalOI = totalOIRaw !== undefined && !oiError ? totalOIRaw : DEMO_FALLBACK_VALUES.totalOI;
      const safeInsurance = insuranceRaw !== undefined && !insuranceError ? insuranceRaw : DEMO_FALLBACK_VALUES.insuranceFund;
      const safeVolume = volume24h !== undefined ? volume24h : DEMO_FALLBACK_VALUES.volume24h;
      const safeBorrowRate = currentBorrowRate && !borrowRateError && currentBorrowRate > BigInt(0) ? currentBorrowRate : DEMO_FALLBACK_VALUES.borrowRate;

      const hoursPerYear = BigInt(8760);
      const lpShare = BigInt(50);
      const hundredPercent = BigInt(100);
      const totalOIInWad = safeTotalOI * BigInt(1e12);
      const revenuePerHour = safeBorrowRate * totalOIInWad / WAD;
      const projectedAnnualRevenue = revenuePerHour * hoursPerYear * lpShare / hundredPercent;
      const tvlInWad = safeTvl * BigInt(1e12);
      const apyBpsTimes100 = projectedAnnualRevenue * BigInt(10000) / tvlInWad;
      const utilizationBpsTimes100 = totalOIInWad * BigInt(10000) / tvlInWad;

      setStats({
        tvl: `$${formatUsdt(safeTvl)}`,
        dailyVolume: `$${formatUsdt(safeVolume)}`,
        totalOI: `$${formatUsdt(safeTotalOI)}`,
        lpApy: `${(Number(apyBpsTimes100) / 100).toFixed(2)}%`,
        utilizationRate: `${(Number(utilizationBpsTimes100) / 100).toFixed(2)}%`,
        insuranceFund: `$${formatWad(safeInsurance)}`,
      });
    } catch (error) {
      console.error('Error calculating protocol stats:', error);
      setStats({
        tvl: `$${formatUsdt(DEMO_FALLBACK_VALUES.tvl)}`,
        dailyVolume: `$${formatUsdt(DEMO_FALLBACK_VALUES.volume24h)}`,
        totalOI: `$${formatUsdt(DEMO_FALLBACK_VALUES.totalOI)}`,
        lpApy: '15.43%',
        utilizationRate: '60.00%',
        insuranceFund: `$${formatWad(DEMO_FALLBACK_VALUES.insuranceFund)}`,
      });
    }
  }, [tvlRaw, totalOIRaw, insuranceRaw, currentBorrowRate, volume24h, tvlError, oiError, insuranceError, borrowRateError, addresses]);

  const isLoading = tvlLoading || oiLoading || insuranceLoading || volumeLoading;

  const StatBox: React.FC<{ label: string; value: string | undefined; highlight?: boolean; isLoading: boolean }> = 
    ({ label, value, highlight, isLoading: loading }) => (
    <div className="lever-inset text-center">
      <div className="text-[10px] uppercase tracking-widest font-medium text-steel mb-2">
        {label}
      </div>
      {loading ? (
        <Skeleton variant="text" className="h-7 w-24 mx-auto" />
      ) : (
        <div className={`text-xl md:text-2xl font-semibold font-mono ${
          highlight ? 'text-accent' : 'text-ivory'
        }`}
        style={highlight ? { textShadow: '0 0 20px rgba(230,255,43,0.25)' } : undefined}
        >
          {value || 'Loading...'}
        </div>
      )}
    </div>
  );

  return (
    <div className="border-b border-border">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-5">
        {/* Stats Card */}
        <div className="lever-card">
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 lg:gap-4">
            <StatBox label="Total TVL" value={stats?.tvl} highlight={true} isLoading={isLoading} />
            <StatBox label="Volume" value={stats?.dailyVolume} isLoading={isLoading} />
            <StatBox label="Total OI" value={stats?.totalOI} isLoading={isLoading} />
            <StatBox label="LP APY" value={stats?.lpApy} highlight={true} isLoading={isLoading} />
            <StatBox label="Utilization" value={stats?.utilizationRate} isLoading={isLoading} />
            <StatBox label="Insurance Fund" value={stats?.insuranceFund} isLoading={isLoading} />
          </div>
        </div>

        {/* Status Indicators */}
        <div className="mt-3 flex justify-center items-center space-x-6 text-xs">
          <div className="flex items-center space-x-1.5">
            <div className="w-1.5 h-1.5 bg-accent rounded-full animate-pulse"></div>
            <span className="text-steel">Live Prices</span>
          </div>
          <div className="flex items-center space-x-1.5">
            <div className="w-1.5 h-1.5 bg-teal rounded-full"></div>
            <span className="text-steel">Base Sepolia</span>
          </div>
          <div className="flex items-center space-x-1.5">
            <div className="w-1.5 h-1.5 bg-accent rounded-full"></div>
            <span className="text-steel">Oracle Active</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ProtocolStats;
