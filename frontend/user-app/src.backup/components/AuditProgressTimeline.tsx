import React from 'react';
import LiveDataIndicator from './LiveDataIndicator';

interface AuditProgressTimelineProps {
  compact?: boolean;
  className?: string;
}

const AuditProgressTimeline: React.FC<AuditProgressTimelineProps> = ({
  compact = false,
  className = ''
}) => {
  const auditSteps = [
    {
      id: 1,
      label: 'Code Review',
      status: 'complete',
      date: '2026-03-10',
      description: 'Smart contract code analysis completed'
    },
    {
      id: 2,
      label: 'Security Testing',
      status: 'complete',
      date: '2026-03-14',
      description: 'Vulnerability assessment and penetration testing'
    },
    {
      id: 3,
      label: 'Formal Verification',
      status: 'current',
      date: '2026-03-18',
      description: 'Mathematical proof verification in progress'
    },
    {
      id: 4,
      label: 'Report Generation',
      status: 'pending',
      date: '2026-03-25',
      description: 'Final audit report compilation'
    },
    {
      id: 5,
      label: 'Publication',
      status: 'pending',
      date: '2026-03-30',
      description: 'Public audit report release'
    }
  ];

  const currentStep = auditSteps.find(step => step.status === 'current');
  const completedSteps = auditSteps.filter(step => step.status === 'complete').length;
  const totalSteps = auditSteps.length;
  const progress = (completedSteps / totalSteps) * 100;

  if (compact) {
    return (
      <div className={`lever-badge-audit-progress ${className}`}>
        <div className="flex items-center space-x-2">
          <div className="w-1.5 h-1.5 bg-accent rounded-full animate-pulse" />
          <span className="text-xs font-mono font-semibold text-accent">
            AUDIT {Math.round(progress)}%
          </span>
          <span className="text-xs text-steel/70 font-mono">
            {currentStep?.label || 'IN PROGRESS'}
          </span>
        </div>
      </div>
    );
  }

  return (
    <div className={`bg-surface-2 border border-border rounded-lg p-4 ${className}`}>
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center space-x-2">
          <div className="w-2 h-2 bg-accent rounded-full animate-pulse" />
          <span className="font-semibold text-accent">Security Audit Progress</span>
        </div>
        <div className="text-sm text-steel">
          {completedSteps}/{totalSteps} Complete
        </div>
      </div>

      {/* Progress Bar */}
      <div className="mb-4">
        <div className="flex items-center justify-between text-sm text-steel/70 mb-2">
          <span>Overall Progress</span>
          <span>{Math.round(progress)}%</span>
        </div>
        <div className="w-full bg-surface-3 rounded-full h-2">
          <div
            className="bg-gradient-to-r from-accent/80 to-accent rounded-full h-2 transition-all duration-500"
            style={{ width: `${progress}%` }}
          />
        </div>
      </div>

      {/* Timeline Steps */}
      <div className="space-y-3">
        {auditSteps.map((step, index) => {
          const isLast = index === auditSteps.length - 1;

          return (
            <div key={step.id} className="relative">
              <div className="flex items-start space-x-3">
                {/* Status Icon */}
                <div className="flex flex-col items-center">
                  <div className={`w-3 h-3 rounded-full border-2 flex-shrink-0 ${
                    step.status === 'complete'
                      ? 'bg-long border-long'
                      : step.status === 'current'
                      ? 'bg-accent border-accent animate-pulse'
                      : 'bg-surface-3 border-steel/30'
                  }`} />
                  {!isLast && (
                    <div className={`w-0.5 h-8 mt-1 ${
                      step.status === 'complete' ? 'bg-long/30' : 'bg-steel/20'
                    }`} />
                  )}
                </div>

                {/* Content */}
                <div className="flex-1 min-w-0 pb-4">
                  <div className="flex items-center justify-between mb-1">
                    <span className={`text-sm font-medium ${
                      step.status === 'complete'
                        ? 'text-long'
                        : step.status === 'current'
                        ? 'text-accent'
                        : 'text-steel/60'
                    }`}>
                      {step.label}
                    </span>
                    <span className="text-xs text-steel/60 font-mono">
                      {step.date}
                    </span>
                  </div>
                  <p className="text-xs text-steel/70">
                    {step.description}
                  </p>

                  {step.status === 'current' && (
                    <div className="mt-2">
                      <LiveDataIndicator
                        label="AUDITOR"
                        value="ACTIVE"
                        status="live"
                        compact={true}
                      />
                    </div>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Auditor Information */}
      <div className="mt-4 pt-4 border-t border-border/50">
        <div className="flex items-center justify-between text-xs">
          <div className="flex items-center space-x-2">
            <span className="text-steel/60">Auditing Firm:</span>
            <span className="text-ivory font-mono">ConsenSys Diligence</span>
          </div>
          <div className="flex items-center space-x-2">
            <span className="text-steel/60">Expected Completion:</span>
            <span className="text-accent font-mono">March 30, 2026</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default AuditProgressTimeline;