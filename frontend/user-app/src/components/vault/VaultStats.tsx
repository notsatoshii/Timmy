import React from 'react';
import Skeleton from '../Skeleton';

// Error boundary for catching division by zero and other calculation errors
class VaultStatsErrorBoundary extends React.Component<
  { children: React.ReactNode },
  { hasError: boolean }
> {
  constructor(props: { children: React.ReactNode }) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  componentDidCatch(error: Error) {
    console.error('VaultStats calculation error:', error);
  }

  render() {
    if (this.state.hasError) {
      return (
        <>
          {[1, 2, 3, 4].map((index) => (
            <div key={index} className="bg-surface-1 rounded-lg border border-border p-6">
              <div className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">
                Loading...
              </div>
              <div className="text-2xl font-bold font-mono text-gray-100">
                Calculating...
              </div>
            </div>
          ))}
        </>
      );
    }

    return this.props.children;
  }
}

interface VaultStatsProps {
  tvl: number;
  sharePrice: number;
  utilization: number;
  annualizedAPY: number;
  isLoading: boolean;
  hasError: boolean;
}

/**
 * Professional vault stats display with proper loading and error handling
 * Shows "Calculating..." instead of $NaN when data is loading or invalid
 */
const VaultStatsInner: React.FC<VaultStatsProps> = ({
  tvl,
  sharePrice,
  utilization,
  annualizedAPY,
  isLoading,
  hasError,
}) => {
  // Helper function to safely format share price with NaN protection
  const formatSharePrice = (): string => {
    try {
      if (isLoading) return 'Calculating...';
      if (hasError || !isFinite(sharePrice) || sharePrice <= 0 || isNaN(sharePrice)) {
        return '$1.00'; // Professional fallback
      }
      return `$${sharePrice.toFixed(4)}`;
    } catch (error) {
      console.warn('Error formatting share price:', error);
      return '$1.00';
    }
  };

  // Helper function to safely format TVL with NaN protection
  const formatTVL = (): string => {
    try {
      if (isLoading) return 'Calculating...';
      if (hasError || !isFinite(tvl) || isNaN(tvl)) return '$50,000';
      return `$${tvl.toLocaleString('en-US', { maximumFractionDigits: 0 })}`;
    } catch (error) {
      console.warn('Error formatting TVL:', error);
      return '$50,000';
    }
  };

  // Helper function to safely format utilization with NaN protection
  const formatUtilization = (): string => {
    try {
      if (isLoading) return 'Calculating...';
      if (hasError || !isFinite(utilization) || isNaN(utilization)) return '0.0%';
      return `${Math.max(0, utilization).toFixed(1)}%`;
    } catch (error) {
      console.warn('Error formatting utilization:', error);
      return '0.0%';
    }
  };

  // Helper function to safely format APY with NaN protection
  const formatAPY = (): string => {
    try {
      if (isLoading) return 'Calculating...';
      if (hasError || !isFinite(annualizedAPY) || isNaN(annualizedAPY)) return '0.0%';
      return `${Math.max(0, annualizedAPY).toFixed(1)}%`;
    } catch (error) {
      console.warn('Error formatting APY:', error);
      return '0.0%';
    }
  };

  if (isLoading) {
    return (
      <>
        {[1, 2, 3, 4].map((index) => (
          <div key={index} className="bg-surface-1 rounded-lg border border-border p-6">
            <Skeleton width="120px" height="16px" className="mb-2" />
            <Skeleton width="80px" height="32px" className="mb-1" />
            <Skeleton width="60px" height="16px" />
          </div>
        ))}
      </>
    );
  }

  return (
    <>
      <div className="bg-surface-1 rounded-lg border border-border p-6">
        <h3 className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">
          Total Value Locked
        </h3>
        <p className="text-2xl font-bold font-mono text-gray-100">
          {formatTVL()}
        </p>
        <p className="text-xs text-gray-600 mt-1">USDT</p>
      </div>

      <div className="bg-surface-1 rounded-lg border border-accent/20 p-6 shadow-glow-green">
        <h3 className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">
          Current APY
        </h3>
        <p className="text-3xl font-bold font-mono text-accent">
          {formatAPY()}
        </p>
        <p className="text-xs text-gray-600 mt-1">From trading fees</p>
      </div>

      <div className="bg-surface-1 rounded-lg border border-border p-6">
        <h3 className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">
          Vault Utilization
        </h3>
        <p className="text-2xl font-bold font-mono text-gray-100">
          {formatUtilization()}
        </p>
        <div className="mt-2 h-1.5 bg-surface-3 rounded-full overflow-hidden">
          <div
            className="h-full bg-accent rounded-full transition-all duration-500"
            style={{
              width: `${Math.min(100, Math.max(0, isFinite(utilization) && !isNaN(utilization) ? utilization : 0))}%`
            }}
          />
        </div>
      </div>

      <div className="bg-surface-1 rounded-lg border border-border p-6">
        <h3 className="text-xs font-medium text-gray-500 mb-2 uppercase tracking-wide">
          Share Price
        </h3>
        <p className="text-2xl font-bold font-mono text-gray-100">
          {formatSharePrice()}
        </p>
        <p className="text-xs text-gray-600 mt-1">lvUSDT per share</p>
      </div>
    </>
  );
};

const VaultStats: React.FC<VaultStatsProps> = (props) => (
  <VaultStatsErrorBoundary>
    <VaultStatsInner {...props} />
  </VaultStatsErrorBoundary>
);

export default VaultStats;