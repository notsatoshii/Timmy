import React from 'react';

interface TestnetDisclaimerProps {
  compact?: boolean;
  context?: 'trading' | 'vault' | 'general';
}

const TestnetDisclaimer: React.FC<TestnetDisclaimerProps> = ({ compact = false, context = 'general' }) => {
  const getContextualMessage = () => {
    switch (context) {
      case 'trading':
        return 'All trading activities use test tokens on Base Sepolia testnet. No real money is involved.';
      case 'vault':
        return 'LP deposits use test USDT tokens. No real funds are at risk in this testnet environment.';
      default:
        return 'This is a testnet deployment for demonstration and testing purposes only.';
    }
  };

  if (compact) {
    return (
      <div className="bg-warning/10 border border-warning/30 rounded-lg p-3">
        <div className="flex items-start space-x-2">
          <div className="w-1.5 h-1.5 bg-warning rounded-full mt-2 flex-shrink-0"></div>
          <p className="text-sm text-steel">
            <span className="font-medium text-warning">Testnet:</span> {getContextualMessage()}
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="lever-card bg-gradient-to-br from-warning/5 via-surface-1 to-surface-1 border-warning/20">
      <div className="flex items-start space-x-4">
        <div className="w-10 h-10 bg-warning/20 rounded-lg flex items-center justify-center flex-shrink-0">
          <svg className="w-5 h-5 text-warning" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </div>

        <div className="flex-1">
          <h3 className="font-semibold text-warning mb-2">Testnet Environment Notice</h3>

          <div className="space-y-3 text-sm text-steel">
            <p>{getContextualMessage()}</p>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div>
                <h4 className="font-medium text-ivory mb-1">Current Status</h4>
                <ul className="space-y-1 text-xs">
                  <li className="flex items-center space-x-2">
                    <div className="w-1 h-1 bg-green-500 rounded-full"></div>
                    <span>Deployed on Base Sepolia</span>
                  </li>
                  <li className="flex items-center space-x-2">
                    <div className="w-1 h-1 bg-yellow-500 rounded-full"></div>
                    <span>Security audit in progress</span>
                  </li>
                  <li className="flex items-center space-x-2">
                    <div className="w-1 h-1 bg-orange-500 rounded-full"></div>
                    <span>Mainnet launch planned Q2 2026</span>
                  </li>
                </ul>
              </div>

              <div>
                <h4 className="font-medium text-ivory mb-1">What This Means</h4>
                <ul className="space-y-1 text-xs">
                  <li className="flex items-center space-x-2">
                    <div className="w-1 h-1 bg-teal rounded-full"></div>
                    <span>Test tokens only (no real value)</span>
                  </li>
                  <li className="flex items-center space-x-2">
                    <div className="w-1 h-1 bg-teal rounded-full"></div>
                    <span>Data may be reset during testing</span>
                  </li>
                  <li className="flex items-center space-x-2">
                    <div className="w-1 h-1 bg-teal rounded-full"></div>
                    <span>Full functionality preview</span>
                  </li>
                </ul>
              </div>
            </div>

            <div className="bg-surface-2/50 rounded-lg p-3 mt-3">
              <p className="text-xs font-medium text-accent mb-1">Next Steps to Mainnet</p>
              <p className="text-xs">
                Security audits → Bug bounty program → Mainnet deployment with real funds.
                Visit the <span className="text-accent">Roadmap</span> tab for detailed timeline.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default TestnetDisclaimer;