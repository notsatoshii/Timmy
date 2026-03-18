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

interface FallbackStatus {
  tvlFallback: boolean;
  oiFallback: boolean;
  insuranceFallback: boolean;
  volumeFallback: boolean;
  apyFallback: boolean;
}

const ProtocolStats: React.FC = () => {
  const [stats, setStats] = useState<ProtocolStatsData | null>(null);
  const [fallbackStatus, setFallbackStatus] = useState<FallbackStatus>({
    tvlFallback: false,
    oiFallback: false,
    insuranceFallback: false,
    volumeFallback: false,
    apyFallback: false,
  });
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
      const tvlFallback = !(tvlRaw && !tvlError);
      const oiFallback = !(totalOIRaw !== undefined && !oiError);
      const insuranceFallback = !(insuranceRaw !== undefined && !insuranceError);
      const volumeFallback = !(volume24h !== undefined);
      const borrowRateFallback = !(currentBorrowRate && !borrowRateError && currentBorrowRate > BigInt(0));

      const safeTvl = tvlFallback ? DEMO_FALLBACK_VALUES.tvl : tvlRaw;
      const safeTotalOI = oiFallback ? DEMO_FALLBACK_VALUES.totalOI : totalOIRaw;
      const safeInsurance = insuranceFallback ? DEMO_FALLBACK_VALUES.insuranceFund : insuranceRaw;
      const safeVolume = volumeFallback ? DEMO_FALLBACK_VALUES.volume24h : volume24h;
      const safeBorrowRate = borrowRateFallback ? DEMO_FALLBACK_VALUES.borrowRate : currentBorrowRate;

      const hoursPerYear = BigInt(8760);
      const lpShare = BigInt(50);
      const hundredPercent = BigInt(100);
      const totalOIInWad = safeTotalOI * BigInt(1e12);
      const revenuePerHour = safeBorrowRate * totalOIInWad / WAD;
      const projectedAnnualRevenue = revenuePerHour * hoursPerYear * lpShare / hundredPercent;
      const tvlInWad = safeTvl * BigInt(1e12);
      const apyBpsTimes100 = projectedAnnualRevenue * BigInt(10000) / tvlInWad;
      const utilizationBpsTimes100 = totalOIInWad * BigInt(10000) / tvlInWad;

      const apyFallback = tvlFallback || oiFallback || borrowRateFallback;

      setFallbackStatus({
        tvlFallback,
        oiFallback,
        insuranceFallback,
        volumeFallback,
        apyFallback,
      });

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
      setFallbackStatus({
        tvlFallback: true,
        oiFallback: true,
        insuranceFallback: true,
        volumeFallback: true,
        apyFallback: true,
      });
      setStats({
        tvl: `$${formatUsdt(DEMO_FALLBACK_VALUES.tvl)} (Demo)`,
        dailyVolume: `$${formatUsdt(DEMO_FALLBACK_VALUES.volume24h)} (Demo)`,
        totalOI: `$${formatUsdt(DEMO_FALLBACK_VALUES.totalOI)} (Demo)`,
        lpApy: '15.43% (Demo)',
        utilizationRate: '60.00% (Demo)',
        insuranceFund: `$${formatWad(DEMO_FALLBACK_VALUES.insuranceFund)} (Demo)`,
      });
    }
  }, [tvlRaw, totalOIRaw, insuranceRaw, currentBorrowRate, volume24h, tvlError, oiError, insuranceError, borrowRateError, addresses]);

  const isLoading = tvlLoading || oiLoading || insuranceLoading || volumeLoading;

  const StatBox: React.FC<{ label: string; value: string | undefined; highlight?: boolean; isLoading: boolean; isFallback?: boolean }> =
    ({ label, value, highlight, isLoading: loading, isFallback }) => (
    <div className="lever-inset text-center">
      <div className="text-[10px] uppercase tracking-widest font-medium text-steel mb-2 flex items-center justify-center space-x-1">
        <span>{label}</span>
        {isFallback && (
          <span className="bg-yellow-600/20 text-yellow-400 px-1 rounded text-[8px] border border-yellow-600/40">
            DEMO
          </span>
        )}
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
            <StatBox label="Total TVL" value={stats?.tvl} highlight={true} isLoading={isLoading} isFallback={fallbackStatus.tvlFallback} />
            <StatBox label="Volume" value={stats?.dailyVolume} isLoading={isLoading} isFallback={fallbackStatus.volumeFallback} />
            <StatBox label="Total OI" value={stats?.totalOI} isLoading={isLoading} isFallback={fallbackStatus.oiFallback} />
            <StatBox label="LP APY" value={stats?.lpApy} highlight={true} isLoading={isLoading} isFallback={fallbackStatus.apyFallback} />
            <StatBox label="Utilization" value={stats?.utilizationRate} isLoading={isLoading} isFallback={fallbackStatus.oiFallback || fallbackStatus.tvlFallback} />
            <StatBox label="Insurance Fund" value={stats?.insuranceFund} isLoading={isLoading} isFallback={fallbackStatus.insuranceFallback} />
          </div>
        </div>

        {/* Status Indicators */}
        <div className="mt-3 space-y-2">
          <div className="flex justify-center items-center space-x-6 text-xs">
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

          {/* Audit & Deployment Status */}
          <div className="flex justify-center items-center space-x-6 text-xs">
            <div className="flex items-center space-x-1.5">
              <div className="w-1.5 h-1.5 bg-yellow-500 rounded-full"></div>
              <span className="text-steel">Audit: In Progress</span>
            </div>
            <div className="flex items-center space-x-1.5">
              <div className="w-1.5 h-1.5 bg-orange-500 rounded-full"></div>
              <span className="text-steel">Mainnet: Q2 2026</span>
            </div>
            <div className="flex items-center space-x-1.5">
              <div className="w-1.5 h-1.5 bg-blue-500 rounded-full"></div>
              <span className="text-steel">Security Review: Pending</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ProtocolStats;
