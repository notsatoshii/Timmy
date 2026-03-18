import React from 'react';

interface SecurityBadgesProps {
  className?: string;
  showAll?: boolean;
}

const SecurityBadges: React.FC<SecurityBadgesProps> = ({ className = '', showAll = false }) => {
  const badges = [
    {
      id: 'security-audit',
      label: 'Security Audited',
      sublabel: 'Smart Contracts',
      status: 'pending',
      icon: '🔒',
      color: 'purple',
    },
    {
      id: 'risk-assessment',
      label: 'Risk Assessment',
      sublabel: 'Institutional Grade',
      status: 'active',
      icon: '⚡',
      color: 'accent',
    },
    {
      id: 'compliance',
      label: 'Compliance Review',
      sublabel: 'Legal Framework',
      status: 'pending',
      icon: '⚖️',
      color: 'teal',
    },
    {
      id: 'insurance-backed',
      label: 'Insurance Fund',
      sublabel: 'Protocol Protection',
      status: 'active',
      icon: '🛡️',
      color: 'long',
    },
  ];

  const visibleBadges = showAll ? badges : badges.filter(b => b.status === 'active');

  if (visibleBadges.length === 0) return null;

  return (
    <div className={`${className}`}>
      <div className="flex items-center space-x-3 overflow-x-auto pb-2">
        {visibleBadges.map((badge) => (
          <div
            key={badge.id}
            className={`lever-badge-${badge.color} flex-shrink-0`}
          >
            <div className="flex items-center space-x-2">
              <span className="text-sm">{badge.icon}</span>
              <div className="flex flex-col">
                <span className={`text-xs font-semibold font-mono text-${badge.color}`}>
                  {badge.label}
                </span>
                <span className="text-[10px] text-steel/70 leading-none">
                  {badge.sublabel}
                </span>
              </div>
              {badge.status === 'active' && (
                <div className={`w-1.5 h-1.5 bg-${badge.color} rounded-full animate-pulse`} />
              )}
              {badge.status === 'pending' && (
                <div className={`w-1.5 h-1.5 bg-${badge.color}/40 rounded-full`} />
              )}
            </div>
          </div>
        ))}
      </div>

      {showAll && (
        <div className="mt-3 text-center">
          <p className="text-xs text-steel/60">
            Security audits pending mainnet deployment •
            <a href="#security" className="text-accent hover:text-accent/80 transition-colors ml-1">
              Learn more
            </a>
          </p>
        </div>
      )}
    </div>
  );
};

export default SecurityBadges;