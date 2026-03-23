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
import { useRealAPY } from '../hooks/useRealAPY';
import Skeleton from './Skeleton';
import { useVolumeCalculation } from '../hooks/useVolumeCalculation';
import { LiveDataBadge } from './ConnectionStatus';
import LiveDataIndicator from './LiveDataIndicator';

interface ProtocolStatsData {
  tvl: string;
  totalVolume: string;
  totalOI: string;
  lpApy: string;
  utilizationRate: string;
  insuranceFund: string;
}

const DEMO_FALLBACK_VALUES = {
  tvl: BigInt("50000000000"),
  totalOI: BigInt("30000000000"),
  insuranceFund: BigInt("10000000000"),
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

interface ProtocolStatsProps {
  activeTab?: string;
  positionStats?: {
    netPnl: string;
    totalEquity: string;
    lockedCollateral: string;
    activePositions: number;
  };
}

const ProtocolStats: React.FC<ProtocolStatsProps> = ({ activeTab = 'markets', positionStats }) => {
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

  // Read actual USDT balance of insurance fund (not internal WAD accounting)
  const { data: insuranceRaw, isLoading: insuranceLoading, error: insuranceError } = useReadContract({
    address: addresses.usdt,
    abi: [{ name: 'balanceOf', type: 'function', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: '', type: 'uint256' }] }],
    functionName: 'balanceOf',
    args: [addresses.insuranceFund],
    query: { enabled: !!addresses.usdt && !!addresses.insuranceFund }
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

  const { apyPercent: realAPY } = useRealAPY(tvlRaw || BigInt(0));
  useEffect(() => {
    try {
      const tvlFallback = !(tvlRaw !== undefined && !tvlError);
      const oiFallback = !(totalOIRaw !== undefined && !oiError);
      const insuranceFallback = !(insuranceRaw !== undefined && !insuranceError);
      const volumeFallback = !(volume24h !== undefined);
      const borrowRateFallback = !(currentBorrowRate !== undefined && !borrowRateError);

      const safeTvl = tvlFallback ? DEMO_FALLBACK_VALUES.tvl : tvlRaw;
      const safeTotalOI = oiFallback ? DEMO_FALLBACK_VALUES.totalOI : totalOIRaw;

      // Insurance fund: now reads USDT.balanceOf(insuranceFund) directly (6 decimals)
      let safeInsurance: bigint;
      if (insuranceFallback) {
        safeInsurance = DEMO_FALLBACK_VALUES.insuranceFund;
      } else {
        // Already in USDT format (6 decimals) — no conversion needed
        safeInsurance = insuranceRaw as bigint;
        if (safeInsurance < BigInt(0)) {
          safeInsurance = DEMO_FALLBACK_VALUES.insuranceFund;
        }
      }
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
        totalVolume: safeVolume > BigInt(0) ? `$${formatUsdt(safeVolume)}` : '—',
        totalOI: `$${formatUsdt(safeTotalOI)}`,
        lpApy: `${realAPY.toFixed(2)}%`,
        utilizationRate: `${(Number(utilizationBpsTimes100) / 100).toFixed(2)}%`,
        insuranceFund: `$${formatUsdt(safeInsurance)}`,
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
        tvl: `$${formatUsdt(DEMO_FALLBACK_VALUES.tvl)}`,
        totalVolume: `$${formatUsdt(DEMO_FALLBACK_VALUES.volume24h)}`,
        totalOI: `$${formatUsdt(DEMO_FALLBACK_VALUES.totalOI)}`,
        lpApy: 'Demo Data',
        utilizationRate: '60.00%',
        insuranceFund: `$${formatUsdt(DEMO_FALLBACK_VALUES.insuranceFund)}`,
      });
    }
  }, [tvlRaw, totalOIRaw, insuranceRaw, currentBorrowRate, volume24h, tvlError, oiError, insuranceError, borrowRateError, addresses]);

  const isLoading = tvlLoading || oiLoading || insuranceLoading || volumeLoading;

  const StatBox: React.FC<{ label: string; value: string | undefined; highlight?: boolean; isLoading: boolean; isFallback?: boolean }> =
    ({ label, value, highlight, isLoading: loading, isFallback }) => (
    <div className="lever-inset text-center">
      <div className="text-[10px] uppercase tracking-widest font-medium text-steel mb-2 flex items-center justify-center space-x-1">
        <span>{label}</span>
        {isFallback ? (
          <span className="bg-warning/20 text-warning px-1.5 py-0.5 rounded text-[9px] border border-warning/40 font-semibold">
            DEMO DATA
          </span>
        ) : (
          <span className="bg-long/20 text-long px-1.5 py-0.5 rounded text-[9px] border border-long/40 font-semibold flex items-center space-x-1">
            <span className="w-1 h-1 bg-long rounded-full animate-pulse"></span>
            <span>LIVE</span>
          </span>
        )}
      </div>
      {loading ? (
        <Skeleton variant="text" className="h-7 w-24 mx-auto" />
      ) : (
        <div className={`text-lg sm:text-xl md:text-2xl font-semibold font-mono truncate ${
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
    <div className="border-b border-border overflow-hidden">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-5">
        {/* Enhanced Professional Stats Card */}
        <div className="lever-card-institutional overflow-hidden">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 sm:gap-4 lg:gap-6">
            {activeTab === 'markets' && (
              <>
                <StatBox label="Total TVL" value={stats?.tvl} highlight={true} isLoading={isLoading} isFallback={fallbackStatus.tvlFallback} />
                <StatBox label="Total Volume" value={stats?.totalVolume} isLoading={isLoading} isFallback={fallbackStatus.volumeFallback} />
                <StatBox label="Total OI" value={stats?.totalOI} isLoading={isLoading} isFallback={fallbackStatus.oiFallback} />
                <StatBox label="Utilization" value={stats?.utilizationRate} isLoading={isLoading} isFallback={fallbackStatus.oiFallback || fallbackStatus.tvlFallback} />
              </>
            )}
            {activeTab === 'vault' && (
              <>
                <StatBox label="Total TVL" value={stats?.tvl} highlight={true} isLoading={isLoading} isFallback={fallbackStatus.tvlFallback} />
                <StatBox label="Current APY" value={stats?.lpApy} highlight={true} isLoading={isLoading} isFallback={fallbackStatus.apyFallback} />
                <StatBox label="Vault Utilization" value={stats?.utilizationRate} isLoading={isLoading} isFallback={fallbackStatus.oiFallback || fallbackStatus.tvlFallback} />
                <StatBox label="Insurance Fund" value={stats?.insuranceFund} isLoading={isLoading} isFallback={fallbackStatus.insuranceFallback} />
              </>
            )}
            {activeTab === 'positions' && (
              <>
                <StatBox label="Net PnL" value={positionStats?.netPnl ?? '—'} isLoading={isLoading} isFallback={false} />
                <StatBox label="Total Equity" value={positionStats?.totalEquity ?? '—'} isLoading={isLoading} isFallback={false} />
                <StatBox label="Locked Collateral" value={positionStats?.lockedCollateral ?? '—'} isLoading={isLoading} isFallback={false} />
                <StatBox label="Active Positions" value={positionStats?.activePositions?.toString() ?? '0'} isLoading={isLoading} isFallback={false} />
              </>
            )}
          </div>

        </div>

      </div>
    </div>
  );
};

export default ProtocolStats;
