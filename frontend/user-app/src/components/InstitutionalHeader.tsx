import React from 'react';
import { useDemo } from '../contexts/DemoContext';
import { useAccount } from 'wagmi';
import LiveDataIndicator from './LiveDataIndicator';

interface InstitutionalHeaderProps {
  className?: string;
}

const InstitutionalHeader: React.FC<InstitutionalHeaderProps> = ({ className = '' }) => {
  const { isDemoMode } = useDemo();
  const { isConnected } = useAccount();

  const getEnvironmentStatus = () => {
    if (isDemoMode) {
      return {
        label: 'DEMO MODE',
        sublabel: 'Simulated institutional data',
        className: 'lever-status-demo',
        indicatorColor: 'bg-warning',
        textColor: 'text-warning'
      };
    }

    if (isConnected) {
      return {
        label: 'LIVE DATA',
        sublabel: 'Connected to Base Sepolia',
        className: 'lever-status-live',
        indicatorColor: 'bg-long',
        textColor: 'text-long'
      };
    }

    return {
      label: 'READ-ONLY',
      sublabel: 'Live market data feed',
      className: 'lever-status-readonly',
      indicatorColor: 'bg-teal',
      textColor: 'text-teal'
    };
  };

  const status = getEnvironmentStatus();

  return (
    <div className={`${className}`}>
      <div className="bg-surface-1/50 backdrop-blur-sm border-b border-border/30">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="py-3">
            <div className="flex items-center justify-between">
              {/* Environment Status */}
              <div className={`${status.className}`}>
                <div className="flex items-center space-x-2">
                  <div className={`w-2 h-2 rounded-full ${status.indicatorColor} ${isDemoMode ? 'animate-pulse' : ''}`} />
                  <div className="flex flex-col">
                    <span className={`text-xs font-mono font-semibold ${status.textColor}`}>
                      {status.label}
                    </span>
                    <span className="text-[10px] text-steel/70">
                      {status.sublabel}
                    </span>
                  </div>
                </div>
              </div>

              {/* Professional Live Metrics */}
              <div className="hidden md:flex items-center space-x-4">
                <LiveDataIndicator
                  label="NETWORK"
                  value="BASE"
                  status="live"
                  compact={true}
                />
                <div className="w-px h-6 bg-border/30" />
                <LiveDataIndicator
                  label="VERSION"
                  value="1.0.0-β"
                  status="live"
                  compact={true}
                />
                <div className="w-px h-6 bg-border/30" />
                <LiveDataIndicator
                  label="UPTIME"
                  value="99.9%"
                  status="live"
                  compact={true}
                />
                <div className="w-px h-6 bg-border/30" />
                <LiveDataIndicator
                  label="ORACLE"
                  value="ACTIVE"
                  status="live"
                  compact={true}
                />
              </div>

              {/* Enhanced Institutional Badge */}
              <div className="hidden lg:flex items-center space-x-3">
                <div className="lever-badge-audit">
                  <div className="w-1.5 h-1.5 bg-accent rounded-full animate-pulse" />
                  <div className="flex flex-col">
                    <span className="text-xs text-accent font-mono font-bold">
                      INSTITUTIONAL
                    </span>
                    <span className="text-[9px] text-steel/70 leading-none">
                      GRADE PROTOCOL
                    </span>
                  </div>
                </div>
                <div className="lever-badge-security">
                  <span className="text-sm">🛡️</span>
                  <div className="flex flex-col">
                    <span className="text-xs text-purple font-mono font-medium">
                      AUDITS
                    </span>
                    <span className="text-[9px] text-steel/70 leading-none">
                      IN PROGRESS
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default InstitutionalHeader;