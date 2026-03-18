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
        <p className="text-steel text-sm">
          Our path to mainnet launch prioritizes security, thorough testing, and community feedback.
        </p>
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

      {/* Security Emphasis */}
      <div className="mt-8 p-4 bg-blue-900/10 border border-blue-600/20 rounded-lg">
        <div className="flex items-start space-x-3">
          <div className="w-2 h-2 bg-blue-400 rounded-full mt-2"></div>
          <div>
            <h4 className="font-semibold text-blue-400 mb-1">Security First Approach</h4>
            <p className="text-sm text-steel">
              Every phase includes rigorous testing and security reviews. We will not launch on mainnet until
              we are confident in the protocol's security and stability. Your funds' safety is our top priority.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default MainnetRoadmap;