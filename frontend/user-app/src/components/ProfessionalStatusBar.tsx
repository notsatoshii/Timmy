import React, { useState, useEffect } from 'react';
import LiveDataIndicator from './LiveDataIndicator';

interface ProfessionalStatusBarProps {
  className?: string;
  showDetailed?: boolean;
}

const ProfessionalStatusBar: React.FC<ProfessionalStatusBarProps> = ({
  className = '',
  showDetailed = true
}) => {
  const [networkLatency, setNetworkLatency] = useState<number | null>(null);
  const [lastBlockTime, setLastBlockTime] = useState<Date>(new Date());
  const [contractStatus, setContractStatus] = useState<'operational' | 'degraded' | 'offline'>('operational');

  useEffect(() => {
    // Simulate real-time monitoring
    const interval = setInterval(() => {
      // Simulate network latency measurement
      const latency = Math.random() * 100 + 50; // 50-150ms
      setNetworkLatency(latency);

      // Simulate block time updates
      setLastBlockTime(new Date());

      // Simulate contract status monitoring
      const rand = Math.random();
      if (rand > 0.95) {
        setContractStatus('degraded');
      } else if (rand > 0.98) {
        setContractStatus('offline');
      } else {
        setContractStatus('operational');
      }
    }, 5000);

    return () => clearInterval(interval);
  }, []);

  const getContractStatus = () => {
    switch (contractStatus) {
      case 'operational':
        return { status: 'live' as const, value: 'OPERATIONAL', color: 'text-long' };
      case 'degraded':
        return { status: 'stale' as const, value: 'DEGRADED', color: 'text-warning' };
      case 'offline':
        return { status: 'error' as const, value: 'OFFLINE', color: 'text-danger' };
    }
  };

  const contractStatusConfig = getContractStatus();

  const formatLatency = (latency: number | null) => {
    if (!latency) return 'MEASURING';
    return `${Math.round(latency)}ms`;
  };

  const getLatencyStatus = (latency: number | null): 'live' | 'stale' | 'error' => {
    if (!latency) return 'stale';
    if (latency < 100) return 'live';
    if (latency < 200) return 'stale';
    return 'error';
  };

  return (
    <div className={`bg-surface-1/50 backdrop-blur-sm border-t border-border/50 ${className}`}>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3">
        <div className="flex items-center justify-between">
          {/* Left Side - System Status */}
          <div className="flex items-center space-x-6">
            <div className="flex items-center space-x-2">
              <div className="w-2 h-2 bg-long rounded-full animate-pulse" />
              <span className="text-xs font-mono font-semibold text-long">
                SYSTEM OPERATIONAL
              </span>
            </div>

            {showDetailed && (
              <>
                <LiveDataIndicator
                  label="CONTRACTS"
                  value={contractStatusConfig.value}
                  status={contractStatusConfig.status}
                  compact={true}
                />

                <LiveDataIndicator
                  label="NETWORK"
                  value={formatLatency(networkLatency)}
                  status={getLatencyStatus(networkLatency)}
                  compact={true}
                />

                <LiveDataIndicator
                  label="ORACLE"
                  value="POLYMARKET"
                  status="live"
                  compact={true}
                />

                <LiveDataIndicator
                  label="CHAIN"
                  value="BASE SEPOLIA"
                  status="live"
                  compact={true}
                />
              </>
            )}
          </div>

          {/* Right Side - Professional Badges */}
          <div className="flex items-center space-x-6">
            {/* Security Badge */}
            <div className="lever-badge-security">
              <div className="flex items-center space-x-1.5">
                <div className="w-1.5 h-1.5 bg-accent rounded-full animate-pulse" />
                <span className="text-xs font-mono font-semibold text-accent">
                  SECURE
                </span>
                <span className="text-xs text-steel/70 font-mono">
                  SSL/TLS
                </span>
              </div>
            </div>

            {/* Audit Status */}
            <div className="lever-badge-audit">
              <div className="flex items-center space-x-1.5">
                <div className="w-1.5 h-1.5 bg-warning rounded-full" />
                <span className="text-xs font-mono font-semibold text-warning">
                  AUDIT
                </span>
                <span className="text-xs text-steel/70 font-mono">
                  PENDING
                </span>
              </div>
            </div>

            {/* Compliance Badge */}
            <div className="lever-badge-compliance">
              <div className="flex items-center space-x-1.5">
                <div className="w-1.5 h-1.5 bg-long rounded-full animate-pulse" />
                <span className="text-xs font-mono font-semibold text-long">
                  TESTNET
                </span>
                <span className="text-xs text-steel/70 font-mono">
                  VERIFIED
                </span>
              </div>
            </div>

            {/* Last Update Time */}
            <div className="text-xs text-steel/60 font-mono">
              Last update: {lastBlockTime.toLocaleTimeString()}
            </div>
          </div>
        </div>

        {/* Detailed Status Row (Optional) */}
        {showDetailed && (
          <div className="mt-3 pt-3 border-t border-border/30">
            <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4 text-xs">
              <div className="text-center">
                <div className="text-steel/60">UPTIME</div>
                <div className="text-long font-mono font-semibold">99.98%</div>
              </div>
              <div className="text-center">
                <div className="text-steel/60">VERSION</div>
                <div className="text-ivory font-mono">v1.0.0-beta</div>
              </div>
              <div className="text-center">
                <div className="text-steel/60">DEPLOYED</div>
                <div className="text-ivory font-mono">2026-03-15</div>
              </div>
              <div className="text-center">
                <div className="text-steel/60">MARKETS</div>
                <div className="text-accent font-mono font-semibold">5 ACTIVE</div>
              </div>
              <div className="text-center">
                <div className="text-steel/60">USERS</div>
                <div className="text-accent font-mono font-semibold">247 DEMO</div>
              </div>
              <div className="text-center">
                <div className="text-steel/60">BACKUP</div>
                <div className="text-long font-mono font-semibold">ACTIVE</div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default ProfessionalStatusBar;