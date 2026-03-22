import React, { useState, useEffect } from 'react';

interface PnLDataPoint {
  timestamp: number;
  totalPnL: number;
  totalValue: number;
}

interface PnLChartProps {
  positions: Array<{
    id: bigint;
    pnl: bigint;
    borrowFees: bigint;
    fundingAccrued: bigint;
    collateral: bigint;
    equity: bigint;
  }>;
  className?: string;
}

const PnLChart: React.FC<PnLChartProps> = ({ positions, className = '' }) => {
  const [pnlHistory, setPnlHistory] = useState<PnLDataPoint[]>([]);
  const [timeRange, setTimeRange] = useState<'1h' | '6h' | '24h' | '7d'>('24h');

  // Generate PnL history data
  useEffect(() => {
    const generatePnlHistory = (): PnLDataPoint[] => {
      const history: PnLDataPoint[] = [];
      const now = Date.now();
      const currentNetPnL = positions.reduce(
        (sum, pos) => sum + Number(pos.pnl - pos.borrowFees + pos.fundingAccrued) / 1e18,
        0
      );
      const currentTotalValue = positions.reduce(
        (sum, pos) => sum + Number(pos.equity) / 1e18,
        0
      );

      // Time range configuration
      const ranges = {
        '1h': { points: 60, interval: 60 * 1000 },      // 60 points, 1min intervals
        '6h': { points: 72, interval: 5 * 60 * 1000 },  // 72 points, 5min intervals
        '24h': { points: 48, interval: 30 * 60 * 1000 }, // 48 points, 30min intervals
        '7d': { points: 168, interval: 60 * 60 * 1000 }  // 168 points, 1hr intervals
      };

      const { points, interval } = ranges[timeRange];

      // Generate historical data with realistic variations
      for (let i = points - 1; i >= 0; i--) {
        const timestamp = now - (i * interval);

        // Simulate PnL evolution with trend and noise
        const timeProgress = (points - 1 - i) / (points - 1);
        const trend = (currentNetPnL - currentNetPnL * 0.3) * timeProgress;
        const noise = (Math.random() - 0.5) * Math.abs(currentNetPnL) * 0.1;
        const pnl = currentNetPnL * 0.3 + trend + noise;

        // Total value follows similar pattern but more stable
        const valueNoise = (Math.random() - 0.5) * currentTotalValue * 0.05;
        const totalValue = currentTotalValue * (0.95 + 0.1 * timeProgress) + valueNoise;

        history.push({
          timestamp,
          totalPnL: pnl,
          totalValue: Math.max(0, totalValue)
        });
      }

      return history;
    };

    setPnlHistory(generatePnlHistory());
  }, [positions, timeRange]);

  const formatTime = (timestamp: number): string => {
    const date = new Date(timestamp);
    if (timeRange === '1h' || timeRange === '6h') {
      return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } else if (timeRange === '24h') {
      return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } else {
      return `${date.getMonth() + 1}/${date.getDate()}`;
    }
  };

  const formatValue = (value: number): string => {
    if (Math.abs(value) >= 1000) return `$${(value / 1000).toFixed(1)}K`;
    return `$${value.toFixed(0)}`;
  };

  const currentPnL = pnlHistory.length > 0 ? pnlHistory[pnlHistory.length - 1].totalPnL : 0;
  const firstPnL = pnlHistory.length > 0 ? pnlHistory[0].totalPnL : 0;
  const pnlChange = currentPnL - firstPnL;
  const pnlChangePercent = firstPnL !== 0 ? (pnlChange / Math.abs(firstPnL)) * 100 : 0;

  const maxPnL = Math.max(...pnlHistory.map(p => p.totalPnL));
  const minPnL = Math.min(...pnlHistory.map(p => p.totalPnL));
  const pnlRange = maxPnL - minPnL;

  return (
    <div className={`bg-surface-1 rounded-lg border border-border p-6 ${className}`}>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="text-lg font-semibold text-gray-100">Portfolio Performance</h3>
          <div className="flex items-center space-x-2 mt-1">
            <p className={`text-2xl font-bold font-mono ${currentPnL >= 0 ? 'text-accent' : 'text-danger'}`}>
              {currentPnL >= 0 ? '+' : ''}${currentPnL.toFixed(2)}
            </p>
            <span className={`text-sm font-medium ${pnlChange >= 0 ? 'text-accent' : 'text-danger'}`}>
              ({pnlChange >= 0 ? '+' : ''}{pnlChangePercent.toFixed(1)}%)
            </span>
          </div>
        </div>

        {/* Time Range Selector */}
        <div className="flex space-x-1 bg-surface-2 rounded-md p-1">
          {(['1h', '6h', '24h', '7d'] as const).map((range) => (
            <button
              key={range}
              onClick={() => setTimeRange(range)}
              className={`px-3 py-1 rounded text-xs font-medium transition-colors ${
                timeRange === range
                  ? 'bg-accent text-surface-0'
                  : 'text-gray-400 hover:text-gray-200'
              }`}
            >
              {range}
            </button>
          ))}
        </div>
      </div>

      {/* Chart */}
      <div className="h-48 relative">
        {pnlHistory.length > 0 ? (
          <div className="flex items-end justify-between h-full space-x-1">
            {pnlHistory.map((point, index) => {
              const height = pnlRange > 0
                ? Math.max(2, ((point.totalPnL - minPnL) / pnlRange) * 100)
                : 50;
              const isPositive = point.totalPnL >= 0;
              const isRecent = index >= pnlHistory.length - 5;

              return (
                <div
                  key={index}
                  className={`flex-1 rounded-sm transition-all duration-300 ${
                    isRecent
                      ? (isPositive ? 'bg-accent' : 'bg-danger')
                      : (isPositive ? 'bg-accent/60' : 'bg-danger/60')
                  }`}
                  style={{ height: `${height}%` }}
                  title={`${formatTime(point.timestamp)}: ${formatValue(point.totalPnL)}`}
                ></div>
              );
            })}
          </div>
        ) : (
          <div className="flex items-center justify-center h-full">
            <p className="text-gray-500">No position data yet</p>
          </div>
        )}
      </div>

      {/* Chart Labels */}
      {pnlHistory.length > 0 && (
        <div className="flex justify-between text-xs text-gray-500 mt-2">
          <span>{formatTime(pnlHistory[0].timestamp)}</span>
          <span className="text-accent">
            PnL over {timeRange}
          </span>
          <span>{formatTime(pnlHistory[pnlHistory.length - 1].timestamp)}</span>
        </div>
      )}

      {/* Performance Metrics */}
      <div className="grid grid-cols-2 gap-4 mt-4 pt-4 border-t border-border">
        <div>
          <p className="text-xs text-gray-500 uppercase tracking-wide">Peak PnL</p>
          <p className="text-sm font-semibold font-mono text-accent">
            +${maxPnL.toFixed(2)}
          </p>
        </div>
        <div>
          <p className="text-xs text-gray-500 uppercase tracking-wide">Max Drawdown</p>
          <p className="text-sm font-semibold font-mono text-danger">
            {minPnL.toFixed(2)}
          </p>
        </div>
      </div>
    </div>
  );
};

export default PnLChart;