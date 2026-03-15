import React from 'react';

interface MarginData {
  totalCollateral: number;
  totalEquity: number;
  totalNotional: number;
  totalMaintenanceMargin: number;
  totalInitialMargin: number;
  freeCollateral: number;
  marginUtilization: number;
  liquidationDistance: number;
  maxAdditionalSize: number;
}

interface MarginUsageProps {
  positions: Array<{
    id: bigint;
    collateral: bigint;
    equity: bigint;
    positionSize: bigint;
    leverage: bigint;
    pnl: bigint;
    borrowFees: bigint;
    fundingAccrued: bigint;
  }>;
  accountBalance: bigint | undefined;
  freeCollateral: bigint | undefined;
  className?: string;
}

const MarginUsage: React.FC<MarginUsageProps> = ({
  positions,
  accountBalance,
  freeCollateral,
  className = ''
}) => {
  // Calculate margin metrics
  const marginData: MarginData = React.useMemo(() => {
    if (positions.length === 0) {
      return {
        totalCollateral: 0,
        totalEquity: 0,
        totalNotional: 0,
        totalMaintenanceMargin: 0,
        totalInitialMargin: 0,
        freeCollateral: Number(freeCollateral || 0) / 1e18,
        marginUtilization: 0,
        liquidationDistance: 100,
        maxAdditionalSize: Number(accountBalance || 0) / 1e18 * 10, // Assume 10x max leverage for new positions
      };
    }

    const totalCollateral = positions.reduce((sum, pos) => sum + Number(pos.collateral) / 1e18, 0);
    const totalEquity = positions.reduce((sum, pos) => sum + Number(pos.equity) / 1e18, 0);
    const totalNotional = positions.reduce((sum, pos) => sum + Number(pos.positionSize) / 1e18, 0);

    // Estimate margin requirements (simplified)
    // Maintenance margin: 2.5% of notional (base rate)
    // Initial margin: 5% of notional (2x maintenance)
    const totalMaintenanceMargin = totalNotional * 0.025;
    const totalInitialMargin = totalNotional * 0.05;

    const freeCol = Number(freeCollateral || 0) / 1e18;
    const marginUtilization = totalCollateral > 0 ? (totalInitialMargin / (totalCollateral + freeCol)) * 100 : 0;

    // Liquidation distance: how far price can move before liquidation
    const avgLiquidationDistance = positions.length > 0 ? positions.reduce((sum, pos) => {
      const equity = Number(pos.equity) / 1e18;
      const notional = Number(pos.positionSize) / 1e18;
      const maintenanceMargin = notional * 0.025;

      // Distance = (equity - MM) / notional
      const distance = notional > 0 ? Math.max(0, (equity - maintenanceMargin) / notional * 100) : 100;
      return sum + distance;
    }, 0) / positions.length : 100;

    // Max additional size based on free collateral
    const maxAdditionalSize = freeCol * 10; // Assume 10x max leverage for additional positions

    return {
      totalCollateral,
      totalEquity,
      totalNotional,
      totalMaintenanceMargin,
      totalInitialMargin,
      freeCollateral: freeCol,
      marginUtilization: Math.min(100, marginUtilization),
      liquidationDistance: Math.max(0, avgLiquidationDistance),
      maxAdditionalSize,
    };
  }, [positions, accountBalance, freeCollateral]);

  const formatValue = (value: number): string => {
    if (value >= 10000) return `$${(value / 1000).toFixed(1)}K`;
    return `$${value.toFixed(2)}`;
  };

  const formatPercent = (value: number): string => {
    return `${value.toFixed(1)}%`;
  };

  const getUtilizationColor = (utilization: number): string => {
    if (utilization >= 90) return 'text-danger';
    if (utilization >= 70) return 'text-warning';
    return 'text-accent';
  };

  const getUtilizationBarColor = (utilization: number): string => {
    if (utilization >= 90) return 'bg-danger';
    if (utilization >= 70) return 'bg-warning';
    return 'bg-accent';
  };

  const getLiquidationColor = (distance: number): string => {
    if (distance <= 5) return 'text-danger';
    if (distance <= 15) return 'text-warning';
    return 'text-accent';
  };

  return (
    <div className={`bg-surface-1 rounded-lg border border-border p-6 ${className}`}>
      <div className="mb-6">
        <h3 className="text-lg font-semibold text-gray-100">Margin Analysis</h3>
        <p className="text-sm text-gray-500">Risk management and capacity utilization</p>
      </div>

      {/* Margin Utilization Bar */}
      <div className="mb-6">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm font-medium text-gray-300">Margin Utilization</span>
          <span className={`text-sm font-bold ${getUtilizationColor(marginData.marginUtilization)}`}>
            {formatPercent(marginData.marginUtilization)}
          </span>
        </div>

        <div className="w-full bg-surface-3 rounded-full h-3 overflow-hidden">
          <div
            className={`h-full transition-all duration-300 ${getUtilizationBarColor(marginData.marginUtilization)}`}
            style={{ width: `${Math.min(100, marginData.marginUtilization)}%` }}
          />
        </div>

        <div className="flex justify-between text-xs text-gray-600 mt-1">
          <span>0%</span>
          <span className="text-warning">70%</span>
          <span className="text-danger">90%</span>
          <span>100%</span>
        </div>
      </div>

      {/* Key Metrics Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <div className="bg-surface-2 rounded-lg p-4 text-center">
          <h4 className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">
            Total Collateral
          </h4>
          <p className="text-lg font-bold font-mono text-gray-100">
            {formatValue(marginData.totalCollateral)}
          </p>
          <p className="text-xs text-gray-600">Locked in positions</p>
        </div>

        <div className="bg-surface-2 rounded-lg p-4 text-center">
          <h4 className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">
            Free Collateral
          </h4>
          <p className="text-lg font-bold font-mono text-accent">
            {formatValue(marginData.freeCollateral)}
          </p>
          <p className="text-xs text-gray-600">Available to trade</p>
        </div>

        <div className="bg-surface-2 rounded-lg p-4 text-center">
          <h4 className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">
            Maintenance Margin
          </h4>
          <p className="text-lg font-bold font-mono text-warning">
            {formatValue(marginData.totalMaintenanceMargin)}
          </p>
          <p className="text-xs text-gray-600">Required to hold</p>
        </div>

        <div className="bg-surface-2 rounded-lg p-4 text-center">
          <h4 className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">
            Liquidation Distance
          </h4>
          <p className={`text-lg font-bold font-mono ${getLiquidationColor(marginData.liquidationDistance)}`}>
            {formatPercent(marginData.liquidationDistance)}
          </p>
          <p className="text-xs text-gray-600">Avg across positions</p>
        </div>
      </div>

      {/* Capacity Analysis */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        {/* Trading Capacity */}
        <div className="bg-surface-2 rounded-lg p-4">
          <h4 className="text-sm font-medium text-gray-300 mb-3">Trading Capacity</h4>

          <div className="space-y-3">
            <div className="flex justify-between items-center">
              <span className="text-xs text-gray-500">Max Additional Size</span>
              <span className="text-sm font-mono text-accent">
                {formatValue(marginData.maxAdditionalSize)}
              </span>
            </div>

            <div className="flex justify-between items-center">
              <span className="text-xs text-gray-500">Current Notional</span>
              <span className="text-sm font-mono text-gray-300">
                {formatValue(marginData.totalNotional)}
              </span>
            </div>

            <div className="flex justify-between items-center">
              <span className="text-xs text-gray-500">Total Capacity</span>
              <span className="text-sm font-mono text-gray-100 font-semibold">
                {formatValue(marginData.totalNotional + marginData.maxAdditionalSize)}
              </span>
            </div>
          </div>
        </div>

        {/* Risk Metrics */}
        <div className="bg-surface-2 rounded-lg p-4">
          <h4 className="text-sm font-medium text-gray-300 mb-3">Risk Metrics</h4>

          <div className="space-y-3">
            <div className="flex justify-between items-center">
              <span className="text-xs text-gray-500">Portfolio Leverage</span>
              <span className="text-sm font-mono text-gray-300">
                {marginData.totalCollateral > 0 ?
                  `${(marginData.totalNotional / marginData.totalCollateral).toFixed(1)}x` :
                  '0x'
                }
              </span>
            </div>

            <div className="flex justify-between items-center">
              <span className="text-xs text-gray-500">Margin Efficiency</span>
              <span className="text-sm font-mono text-gray-300">
                {marginData.totalMaintenanceMargin > 0 ?
                  formatPercent((marginData.totalEquity / marginData.totalMaintenanceMargin - 1) * 100) :
                  'N/A'
                }
              </span>
            </div>

            <div className="flex justify-between items-center">
              <span className="text-xs text-gray-500">Health Factor</span>
              <span className={`text-sm font-mono ${
                marginData.totalMaintenanceMargin > 0 ?
                  (marginData.totalEquity / marginData.totalMaintenanceMargin >= 1.5 ? 'text-accent' :
                   marginData.totalEquity / marginData.totalMaintenanceMargin >= 1.2 ? 'text-warning' : 'text-danger')
                  : 'text-gray-300'
              }`}>
                {marginData.totalMaintenanceMargin > 0 ?
                  (marginData.totalEquity / marginData.totalMaintenanceMargin).toFixed(2) :
                  '∞'
                }
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Warning Messages */}
      {marginData.marginUtilization >= 90 && (
        <div className="bg-danger-muted border border-danger/20 rounded-lg p-4 mb-4">
          <div className="flex items-start space-x-3">
            <div className="w-5 h-5 bg-danger rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
              <span className="text-white text-xs">!</span>
            </div>
            <div>
              <h4 className="text-sm font-semibold text-danger">High Margin Usage</h4>
              <p className="text-xs text-gray-300 mt-1">
                You're using {formatPercent(marginData.marginUtilization)} of available margin.
                Consider reducing position sizes or adding more collateral to avoid liquidation risk.
              </p>
            </div>
          </div>
        </div>
      )}

      {marginData.liquidationDistance <= 10 && marginData.liquidationDistance > 0 && (
        <div className="bg-warning-muted border border-warning/20 rounded-lg p-4">
          <div className="flex items-start space-x-3">
            <div className="w-5 h-5 bg-warning rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
              <span className="text-surface-0 text-xs font-bold">⚠</span>
            </div>
            <div>
              <h4 className="text-sm font-semibold text-warning">Liquidation Risk</h4>
              <p className="text-xs text-gray-300 mt-1">
                Average liquidation distance is only {formatPercent(marginData.liquidationDistance)}.
                Monitor positions closely and consider partial closes if markets move against you.
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default MarginUsage;