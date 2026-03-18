import React from 'react';

interface RoadmapItem {
  phase: string;
  title: string;
  status: 'completed' | 'in-progress' | 'pending';
  timeline: string;
  description: string;
}

const MainnetRoadmap: React.FC = () => {
  const roadmapItems: RoadmapItem[] = [
    {
      phase: 'Phase 1',
      title: 'Testnet Launch & Testing',
      status: 'completed',
      timeline: 'Q1 2026',
      description: 'Full protocol deployment on Base Sepolia testnet for community testing and feedback.',
    },
    {
      phase: 'Phase 2',
      title: 'Security Audits & Code Review',
      status: 'in-progress',
      timeline: 'Q1-Q2 2026',
      description: 'Comprehensive security audits by leading blockchain security firms. Smart contract formal verification.',
    },
    {
      phase: 'Phase 3',
      title: 'Bug Bounty Program',
      status: 'pending',
      timeline: 'Q2 2026',
      description: 'Public bug bounty program with substantial rewards to identify and fix any remaining vulnerabilities.',
    },
    {
      phase: 'Phase 4',
      title: 'Mainnet Deployment',
      status: 'pending',
      timeline: 'Q2 2026',
      description: 'Official launch on Base Mainnet with full trading capabilities and real funds.',
    },
    {
      phase: 'Phase 5',
      title: 'Ecosystem Expansion',
      status: 'pending',
      timeline: 'Q3+ 2026',
      description: 'Additional market types, cross-chain deployment, and advanced trading features.',
    },
  ];

  const StatusIndicator: React.FC<{ status: RoadmapItem['status'] }> = ({ status }) => {
    switch (status) {
      case 'completed':
        return <div className="w-3 h-3 bg-green-500 rounded-full"></div>;
      case 'in-progress':
        return <div className="w-3 h-3 bg-yellow-500 rounded-full animate-pulse"></div>;
      case 'pending':
        return <div className="w-3 h-3 bg-gray-500 rounded-full"></div>;
    }
  };

  return (
    <div className="lever-card">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-ivory mb-2">Mainnet Deployment Roadmap</h2>
        <p className="text-steel text-sm mb-4">
          Our path to mainnet launch prioritizes security, thorough testing, and community feedback.
        </p>

        {/* Current Status Alert */}
        <div className="bg-warning/10 border border-warning/30 rounded-lg p-4">
          <div className="flex items-center space-x-3">
            <div className="w-3 h-3 bg-warning rounded-full animate-pulse flex-shrink-0"></div>
            <div>
              <h3 className="font-semibold text-warning text-sm">Currently in Testnet Phase</h3>
              <p className="text-steel text-xs mt-1">
                All functionality is operational on Base Sepolia testnet. No real funds are involved.
                This demonstrates the full protocol capabilities in preparation for mainnet launch.
              </p>
            </div>
          </div>
        </div>
      </div>

      <div className="space-y-6">
        {roadmapItems.map((item, index) => (
          <div key={index} className="relative">
            {/* Connection line for all items except the last */}
            {index < roadmapItems.length - 1 && (
              <div className="absolute left-6 top-12 w-px h-12 bg-border"></div>
            )}

            <div className="flex items-start space-x-4">
              <div className="flex-shrink-0 flex items-center justify-center">
                <StatusIndicator status={item.status} />
              </div>

              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between mb-2">
                  <div>
                    <span className="text-xs font-medium text-accent uppercase tracking-wider">
                      {item.phase}
                    </span>
                    <h3 className="text-lg font-semibold text-ivory">{item.title}</h3>
                  </div>
                  <div className="text-right">
                    <div className={`px-2 py-1 rounded text-xs font-medium ${
                      item.status === 'completed'
                        ? 'bg-green-900/20 text-green-400 border border-green-600/30'
                        : item.status === 'in-progress'
                        ? 'bg-yellow-900/20 text-yellow-400 border border-yellow-600/30'
                        : 'bg-gray-900/20 text-gray-400 border border-gray-600/30'
                    }`}>
                      {item.status === 'completed' ? 'COMPLETED' :
                       item.status === 'in-progress' ? 'IN PROGRESS' : 'PENDING'}
                    </div>
                    <div className="text-xs text-steel mt-1">{item.timeline}</div>
                  </div>
                </div>
                <p className="text-sm text-steel leading-relaxed">{item.description}</p>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Security & Audit Information */}
      <div className="mt-8 space-y-4">
        {/* Security Emphasis */}
        <div className="p-4 bg-blue-900/10 border border-blue-600/20 rounded-lg">
          <div className="flex items-start space-x-3">
            <div className="w-8 h-8 bg-blue-600/20 rounded-lg flex items-center justify-center flex-shrink-0">
              <svg className="w-4 h-4 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.031 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
              </svg>
            </div>
            <div>
              <h4 className="font-semibold text-blue-400 mb-2">Security First Approach</h4>
              <p className="text-sm text-steel mb-3">
                Every phase includes rigorous testing and security reviews. We will not launch on mainnet until
                we are confident in the protocol's security and stability. Your funds' safety is our top priority.
              </p>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div>
                  <h5 className="font-medium text-ivory text-xs mb-1">Smart Contract Audits</h5>
                  <ul className="space-y-1">
                    <li className="flex items-center space-x-2">
                      <div className="w-1 h-1 bg-yellow-500 rounded-full"></div>
                      <span className="text-xs text-steel">Lead security firms engaged</span>
                    </li>
                    <li className="flex items-center space-x-2">
                      <div className="w-1 h-1 bg-yellow-500 rounded-full"></div>
                      <span className="text-xs text-steel">Formal verification planned</span>
                    </li>
                    <li className="flex items-center space-x-2">
                      <div className="w-1 h-1 bg-yellow-500 rounded-full"></div>
                      <span className="text-xs text-steel">Public audit reports</span>
                    </li>
                  </ul>
                </div>

                <div>
                  <h5 className="font-medium text-ivory text-xs mb-1">Additional Safeguards</h5>
                  <ul className="space-y-1">
                    <li className="flex items-center space-x-2">
                      <div className="w-1 h-1 bg-teal rounded-full"></div>
                      <span className="text-xs text-steel">Bug bounty program ($100K+)</span>
                    </li>
                    <li className="flex items-center space-x-2">
                      <div className="w-1 h-1 bg-teal rounded-full"></div>
                      <span className="text-xs text-steel">Gradual mainnet rollout</span>
                    </li>
                    <li className="flex items-center space-x-2">
                      <div className="w-1 h-1 bg-teal rounded-full"></div>
                      <span className="text-xs text-steel">Insurance fund protection</span>
                    </li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Testnet Benefits */}
        <div className="p-4 bg-teal/10 border border-teal/20 rounded-lg">
          <div className="flex items-start space-x-3">
            <div className="w-2 h-2 bg-teal rounded-full mt-2"></div>
            <div>
              <h4 className="font-semibold text-teal mb-1">Why We're Starting on Testnet</h4>
              <p className="text-sm text-steel">
                This testnet deployment allows us to thoroughly test all protocol mechanics with real market conditions
                but without financial risk. Community feedback during this phase directly improves mainnet security.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default MainnetRoadmap;