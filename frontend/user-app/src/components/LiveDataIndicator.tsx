import React from 'react';

interface LiveDataIndicatorProps {
  label: string;
  value: string | number;
  sublabel?: string;
  status?: 'live' | 'stale' | 'error' | 'loading';
  trend?: 'up' | 'down' | 'stable';
  className?: string;
  compact?: boolean;
}

const LiveDataIndicator: React.FC<LiveDataIndicatorProps> = ({
  label,
  value,
  sublabel,
  status = 'live',
  trend,
  className = '',
  compact = false
}) => {
  const getStatusColor = () => {
    switch (status) {
      case 'live': return 'long';
      case 'stale': return 'warning';
      case 'error': return 'danger';
      case 'loading': return 'steel';
      default: return 'steel';
    }
  };

  const getTrendIcon = () => {
    switch (trend) {
      case 'up': return '↗';
      case 'down': return '↘';
      case 'stable': return '→';
      default: return null;
    }
  };

  const statusColor = getStatusColor();

  if (compact) {
    return (
      <div className={`lever-badge-live ${className}`}>
        <div className={`w-1.5 h-1.5 bg-${statusColor} rounded-full ${status === 'live' ? 'animate-pulse' : ''}`} />
        <span className={`text-xs font-mono font-semibold text-${statusColor}`}>
          {value}
        </span>
        <span className="text-xs text-steel/70 font-mono">
          {label}
        </span>
      </div>
    );
  }

  return (
    <div className={`lever-metric-card ${className}`}>
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <div className="flex items-center space-x-2 mb-1">
            <div className={`w-2 h-2 bg-${statusColor} rounded-full ${status === 'live' ? 'animate-pulse' : ''}`} />
            <span className="lever-caption text-steel/70">
              {label}
            </span>
            {status === 'live' && (
              <span className="lever-caption text-long">LIVE</span>
            )}
          </div>

          <div className="flex items-baseline space-x-2">
            <span className={`lever-heading-sm text-${statusColor}`}>
              {value}
            </span>
            {trend && (
              <span className={`text-lg text-${trend === 'up' ? 'long' : trend === 'down' ? 'danger' : 'steel'}`}>
                {getTrendIcon()}
              </span>
            )}
          </div>

          {sublabel && (
            <p className="text-xs text-steel/60 mt-1">
              {sublabel}
            </p>
          )}
        </div>

        {status === 'loading' && (
          <div className="lever-loader-spinner w-4 h-4" />
        )}
      </div>
    </div>
  );
};

export default LiveDataIndicator;