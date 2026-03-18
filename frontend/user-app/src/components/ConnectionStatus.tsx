import React from 'react';
import { useAccount } from 'wagmi';
import { useDemo } from '../contexts/DemoContext';

interface ConnectionStatusProps {
  className?: string;
  showLabel?: boolean;
}

const ConnectionStatus: React.FC<ConnectionStatusProps> = ({
  className = '',
  showLabel = true
}) => {
  const { isConnected } = useAccount();
  const { isDemoMode } = useDemo();

  const getStatus = () => {
    if (isDemoMode) {
      return {
        type: 'demo',
        label: 'Demo Mode',
        description: 'Simulated data for demonstration',
        color: 'bg-warning',
        textColor: 'text-warning',
        pulse: true
      };
    }

    if (isConnected) {
      return {
        type: 'live',
        label: 'Live Data',
        description: 'Connected to Base Sepolia testnet',
        color: 'bg-long',
        textColor: 'text-long',
        pulse: false
      };
    }

    return {
      type: 'readonly',
      label: 'Read Only',
      description: 'Viewing live data, connect to trade',
      color: 'bg-teal',
      textColor: 'text-teal',
      pulse: false
    };
  };

  const status = getStatus();

  return (
    <div className={`flex items-center space-x-2 ${className}`}>
      <div className="relative">
        <div
          className={`w-2 h-2 rounded-full ${status.color} ${
            status.pulse ? 'animate-pulse' : ''
          }`}
        />
        {status.pulse && (
          <div className={`absolute inset-0 w-2 h-2 rounded-full ${status.color} animate-ping opacity-75`} />
        )}
      </div>
      {showLabel && (
        <div className="flex flex-col">
          <span className={`text-xs font-medium ${status.textColor}`}>
            {status.label}
          </span>
          <span className="text-[10px] text-steel leading-tight">
            {status.description}
          </span>
        </div>
      )}
    </div>
  );
};

export const LiveDataBadge: React.FC<{ className?: string }> = ({ className = '' }) => {
  const { isDemoMode } = useDemo();

  if (isDemoMode) {
    return (
      <div className={`inline-flex items-center space-x-1.5 bg-warning-muted border border-warning/20 rounded-md px-2 py-1 ${className}`}>
        <div className="w-1.5 h-1.5 bg-warning rounded-full animate-pulse" />
        <span className="text-warning text-xs font-medium">DEMO DATA</span>
      </div>
    );
  }

  return (
    <div className={`inline-flex items-center space-x-1.5 bg-long/10 border border-long/20 rounded-md px-2 py-1 ${className}`}>
      <div className="w-1.5 h-1.5 bg-long rounded-full" />
      <span className="text-long text-xs font-medium">LIVE</span>
    </div>
  );
};

export const NetworkIndicator: React.FC<{ className?: string }> = ({ className = '' }) => {
  const [latency, setLatency] = React.useState<number | null>(null);

  React.useEffect(() => {
    const measureLatency = async () => {
      const start = performance.now();
      try {
        const response = await fetch('https://sepolia.base.org', {
          method: 'HEAD',
          mode: 'no-cors',
          cache: 'no-cache'
        });
        const end = performance.now();
        setLatency(Math.round(end - start));
      } catch (error) {
        setLatency(null);
      }
    };

    measureLatency();
    const interval = setInterval(measureLatency, 30000); // Check every 30 seconds

    return () => clearInterval(interval);
  }, []);

  const getLatencyStatus = (lat: number | null) => {
    if (lat === null) return { color: 'bg-danger', label: 'Offline', ms: '---' };
    if (lat < 100) return { color: 'bg-long', label: 'Excellent', ms: `${lat}ms` };
    if (lat < 300) return { color: 'bg-warning', label: 'Good', ms: `${lat}ms` };
    return { color: 'bg-danger', label: 'Slow', ms: `${lat}ms` };
  };

  const status = getLatencyStatus(latency);

  return (
    <div className={`flex items-center space-x-2 ${className}`}>
      <div className={`w-2 h-2 rounded-full ${status.color}`} />
      <div className="text-right">
        <div className="text-xs text-ivory font-medium">{status.label}</div>
        <div className="text-[10px] text-steel font-mono">{status.ms}</div>
      </div>
    </div>
  );
};

export default ConnectionStatus;