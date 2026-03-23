import React, { useState, useEffect } from 'react';

interface ProfessionalStatusBarProps {
  className?: string;
  showDetailed?: boolean;
}

const ProfessionalStatusBar: React.FC<ProfessionalStatusBarProps> = ({
  className = '',
  showDetailed = true
}) => {
  const [networkLatency, setNetworkLatency] = useState<number | null>(null);

  useEffect(() => {
    const checkHealth = async () => {
      try {
        const start = performance.now();
        await fetch('https://sepolia.base.org', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ jsonrpc: '2.0', method: 'eth_blockNumber', params: [], id: 1 }),
        });
        setNetworkLatency(performance.now() - start);
      } catch {
        setNetworkLatency(null);
      }
    };

    checkHealth();
    const interval = setInterval(checkHealth, 30000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className={`bg-surface-1/30 border-t border-border/30 overflow-hidden ${className}`}>
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-2">
        <div className="flex items-center justify-between">
          {/* Left - System status + key indicators */}
          <div className="flex items-center space-x-4 text-[11px] font-mono">
            <div className="flex items-center space-x-1.5">
              <div className="w-1.5 h-1.5 bg-long rounded-full animate-pulse" />
              <span className="text-long font-semibold">OPERATIONAL</span>
            </div>
            <span className="text-steel/30 hidden sm:inline">|</span>
            <span className="text-steel/60 hidden sm:inline">
              Base Sepolia
            </span>
            <span className="text-steel/30 hidden md:inline">|</span>
            <span className="text-steel/60 hidden md:inline">
              Polymarket Oracle
            </span>
            <span className="text-steel/30 hidden lg:inline">|</span>
            <span className="text-steel/60 hidden lg:inline">
              {networkLatency ? `${Math.round(networkLatency)}ms` : '...'}
            </span>
          </div>

          {/* Right - Version + testnet badge */}
          <div className="flex items-center space-x-4 text-[11px] font-mono">
            <span className="text-steel/40 hidden sm:inline">v1.0.0-beta</span>
            <div className="flex items-center space-x-1.5">
              <div className="w-1.5 h-1.5 bg-long rounded-full" />
              <span className="text-long font-semibold">TESTNET</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ProfessionalStatusBar;