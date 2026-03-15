import React, { Suspense, lazy } from 'react';
import Skeleton from './Skeleton';

// Lazy load the MarketDetail component
const MarketDetailComponent = lazy(() => import('./MarketDetail'));

interface Market {
  id: string;
  description: string;
  price: number;
  resolutionTime: number;
  category: string;
  isLive: boolean;
}

interface LazyMarketDetailProps {
  market: Market;
  onBack: () => void;
  onTradeSelect?: (marketId: string, marketName: string, direction: 'long' | 'short') => void;
}

/**
 * Lazy-loaded market detail component with loading fallback
 * Only loads the heavy MarketDetail component when needed
 */
const LazyMarketDetail: React.FC<LazyMarketDetailProps> = (props) => {
  return (
    <Suspense fallback={<MarketDetailSkeleton />}>
      <MarketDetailComponent {...props} />
    </Suspense>
  );
};

/**
 * Loading skeleton for market detail view
 */
const MarketDetailSkeleton: React.FC = () => {
  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <div className="flex items-center space-x-3 mb-3">
            <Skeleton width="60px" height="32px" />
            <Skeleton width="80px" height="28px" />
            <Skeleton width="50px" height="24px" />
          </div>
          <Skeleton height="32px" className="mb-2" />
          <Skeleton width="60%" height="20px" />
        </div>
        <Skeleton width="80px" height="40px" />
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {[1, 2, 3, 4].map((index) => (
          <div key={index} className="bg-surface-1 rounded-lg border border-border p-4">
            <Skeleton width="80px" height="16px" className="mb-2" />
            <Skeleton width="60px" height="24px" />
          </div>
        ))}
      </div>

      {/* Chart Section */}
      <div className="bg-surface-1 rounded-lg border border-border p-6">
        <div className="flex items-center justify-between mb-4">
          <Skeleton width="120px" height="24px" />
          <div className="flex space-x-2">
            {['1h', '6h', '24h', '7d'].map((period) => (
              <Skeleton key={period} width="40px" height="32px" />
            ))}
          </div>
        </div>
        <Skeleton height="200px" className="rounded" />
      </div>

      {/* OI Breakdown */}
      <div className="bg-surface-1 rounded-lg border border-border p-6">
        <Skeleton width="150px" height="24px" className="mb-4" />
        <div className="space-y-4">
          <div className="flex justify-between items-center">
            <Skeleton width="40px" height="20px" />
            <Skeleton width="80px" height="20px" />
          </div>
          <Skeleton height="8px" className="rounded-full" />
          <div className="flex justify-between items-center">
            <Skeleton width="50px" height="20px" />
            <Skeleton width="80px" height="20px" />
          </div>
        </div>
      </div>

      {/* Recent Positions */}
      <div className="bg-surface-1 rounded-lg border border-border p-6">
        <Skeleton width="140px" height="24px" className="mb-4" />
        <div className="space-y-3">
          {[1, 2, 3, 4].map((index) => (
            <div key={index} className="flex justify-between items-center py-2">
              <div className="flex items-center space-x-3">
                <Skeleton width="50px" height="24px" />
                <Skeleton width="80px" height="16px" />
              </div>
              <div className="flex items-center space-x-4">
                <Skeleton width="60px" height="16px" />
                <Skeleton width="70px" height="16px" />
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Action Buttons */}
      <div className="flex space-x-4">
        <Skeleton width="120px" height="44px" />
        <Skeleton width="120px" height="44px" />
      </div>
    </div>
  );
};

/**
 * Higher-order component for lazy loading with error boundary
 */
export const withLazyLoading = <P extends object>(
  Component: React.ComponentType<P>,
  fallback?: React.ReactNode
) => {
  const LazyComponent = lazy(() => Promise.resolve({ default: Component }));

  return React.forwardRef<any, P>((props, ref) => (
    <Suspense fallback={fallback || <div>Loading...</div>}>
      <LazyComponent {...props} ref={ref} />
    </Suspense>
  ));
};

export default LazyMarketDetail;