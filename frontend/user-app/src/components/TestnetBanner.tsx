import React, { useState } from 'react';
import LiveDataIndicator from './LiveDataIndicator';

const TestnetBanner: React.FC = () => {
  const [isDismissed, setIsDismissed] = useState(false);

  if (isDismissed) {
    return null;
  }

  return (
    <div className="bg-gradient-to-r from-warning/20 via-warning/10 to-warning/20 border-b border-warning/30 relative">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-3">
            <div className="flex items-center space-x-2">
              <div className="w-2 h-2 bg-warning rounded-full animate-pulse"></div>
              <span className="font-semibold text-warning text-sm uppercase tracking-wider">
                TESTNET ENVIRONMENT
              </span>
            </div>
            <span className="text-sm text-steel">
              This is a test deployment on Base Sepolia. No real funds at risk.
            </span>
          </div>

          <div className="flex items-center space-x-4">
            <div className="hidden sm:flex items-center space-x-3">
              <LiveDataIndicator
                label="AUDIT"
                value="PENDING"
                status="stale"
                compact={true}
              />
              <LiveDataIndicator
                label="MAINNET"
                value="Q2 2026"
                status="stale"
                compact={true}
              />
            </div>

            <button
              onClick={() => setIsDismissed(true)}
              className="text-steel hover:text-warning transition-colors p-1"
              aria-label="Dismiss banner"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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