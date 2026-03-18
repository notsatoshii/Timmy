import React, { useState } from 'react';
import LiveDataIndicator from './LiveDataIndicator';

const TestnetBanner: React.FC = () => {
  const [isDismissed, setIsDismissed] = useState(false);

  if (isDismissed) {
    return null;
  }

  return (
    <div className="bg-surface-1/60 backdrop-blur-sm border-b border-border/30 relative">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <div className="flex items-center space-x-2">
              <div className="w-1.5 h-1.5 bg-warning/70 rounded-full"></div>
              <span className="font-medium text-steel text-xs uppercase tracking-wide">
                Demo Environment
              </span>
              <span className="text-xs text-steel/60 font-mono">
                Base Sepolia Testnet
              </span>
            </div>

            {/* Live Data Indicators */}
            <div className="hidden md:flex items-center space-x-3">
              <LiveDataIndicator
                label="STATUS"
                value="DEMO ACTIVE"
                status="live"
                compact={true}
              />
              <LiveDataIndicator
                label="DATA"
                value="LIVE"
                status="live"
                compact={true}
              />
            </div>
          </div>

          <div className="flex items-center space-x-4">
            <div className="hidden sm:flex items-center space-x-2 text-xs">
              <span className="text-steel/60">No real funds •</span>
              <span className="text-accent font-mono">Professional Demo</span>
            </div>

            <button
              onClick={() => setIsDismissed(true)}
              className="text-steel/50 hover:text-steel transition-colors p-1"
              aria-label="Dismiss banner"
            >
              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default TestnetBanner;