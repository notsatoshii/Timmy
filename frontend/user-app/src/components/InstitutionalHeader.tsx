import React from 'react';
import { useDemo } from '../contexts/DemoContext';
import { useAccount } from 'wagmi';

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

              {/* Professional Metrics */}
              <div className="hidden md:flex items-center space-x-6">
                <div className="flex items-center space-x-2">
                  <span className="text-xs text-steel/60 font-mono">NETWORK</span>
                  <div className="flex items-center space-x-1">
                    <div className="w-1.5 h-1.5 bg-long rounded-full" />
                    <span className="text-xs text-long font-mono font-medium">BASE</span>
                  </div>
                </div>

                <div className="flex items-center space-x-2">
                  <span className="text-xs text-steel/60 font-mono">VERSION</span>
                  <span className="text-xs text-accent font-mono font-medium">1.0.0-BETA</span>
                </div>

                <div className="flex items-center space-x-2">
                  <span className="text-xs text-steel/60 font-mono">STATUS</span>
                  <div className="flex items-center space-x-1">
                    <div className="w-1.5 h-1.5 bg-long rounded-full animate-pulse" />
                    <span className="text-xs text-long font-mono font-medium">OPERATIONAL</span>
                  </div>
                </div>
              </div>

              {/* Institutional Badge */}
              <div className="hidden lg:flex items-center space-x-2 bg-gradient-to-r from-accent/5 to-teal/5 border border-accent/20 rounded-md px-3 py-1.5">
                <div className="w-1.5 h-1.5 bg-accent rounded-full animate-pulse" />
                <span className="text-xs text-accent font-mono font-medium">INSTITUTIONAL GRADE</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default InstitutionalHeader;