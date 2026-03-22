import React from 'react';
import LiveDataIndicator from './LiveDataIndicator';

interface ProfessionalLoaderProps {
  title: string;
  subtitle?: string;
  showLiveIndicators?: boolean;
  showProgress?: boolean;
  progressSteps?: string[];
  currentStep?: number;
  size?: 'sm' | 'md' | 'lg' | 'xl';
  variant?: 'default' | 'data' | 'blockchain' | 'trading';
}

const ProfessionalLoader: React.FC<ProfessionalLoaderProps> = ({
  title,
  subtitle,
  showLiveIndicators = false,
  showProgress = false,
  progressSteps = [],
  currentStep = 0,
  size = 'md',
  variant = 'default'
}) => {
  const sizeConfig = {
    sm: { container: 'py-8', icon: 32, title: 'text-lg', subtitle: 'text-sm' },
    md: { container: 'py-12', icon: 48, title: 'text-xl', subtitle: 'text-base' },
    lg: { container: 'py-16', icon: 64, title: 'text-2xl', subtitle: 'text-lg' },
    xl: { container: 'py-24', icon: 80, title: 'text-3xl', subtitle: 'text-xl' },
  };

  const config = sizeConfig[size];

  const getVariantConfig = () => {
    switch (variant) {
      case 'data':
        return {
          icon: '📊',
          color: 'text-accent',
          gradient: 'from-accent/20 to-transparent'
        };
      case 'blockchain':
        return {
          icon: '⛓️',
          color: 'text-long',
          gradient: 'from-long/20 to-transparent'
        };
      case 'trading':
        return {
          icon: '📈',
          color: 'text-warning',
          gradient: 'from-warning/20 to-transparent'
        };
      default:
        return {
          icon: '/lever-icon.png',
          color: 'text-accent',
          gradient: 'from-accent/20 to-transparent'
        };
    }
  };

  const variantConfig = getVariantConfig();

  return (
    <div className={`flex flex-col items-center justify-center ${config.container} space-y-6`}>
      {/* Professional Loading Animation */}
      <div className="relative">
        <style>{`
          @keyframes professional-pulse {
            0%, 100% {
              transform: scale(1);
              filter: drop-shadow(0 0 12px rgba(230,255,43,0.15));
            }
            50% {
              transform: scale(1.05);
              filter: drop-shadow(0 0 24px rgba(230,255,43,0.35));
            }
          }
          @keyframes professional-spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
          }
          .professional-loader {
            animation: professional-pulse 2s ease-in-out infinite,
                       professional-spin 3s linear infinite;
          }
          .loader-ring {
            animation: professional-spin 2s linear infinite reverse;
          }
        `}</style>

        {/* Outer Ring */}
        <div
          className="absolute inset-0 border-2 border-accent/30 rounded-full loader-ring"
          style={{
            width: config.icon + 20,
            height: config.icon + 20,
            left: '-10px',
            top: '-10px',
          }}
        />

        {/* Glow Effect */}
        <div
          className={`absolute inset-0 rounded-full bg-gradient-radial ${variantConfig.gradient}`}
          style={{
            width: config.icon * 2,
            height: config.icon * 2,
            left: -config.icon / 2,
            top: -config.icon / 2,
          }}
        />

        {/* Icon/Logo */}
        {variant === 'default' ? (
          <img
            src="/lever-icon.png"
            alt="Loading"
            className="professional-loader relative z-10"
            style={{ width: config.icon, height: config.icon }}
          />
        ) : (
          <div
            className={`professional-loader relative z-10 flex items-center justify-center text-3xl ${variantConfig.color}`}
            style={{ width: config.icon, height: config.icon }}
          >
            {variantConfig.icon}
          </div>
        )}
      </div>

      {/* Title and Subtitle */}
      <div className="text-center space-y-2">
        <h3 className={`font-semibold ${variantConfig.color} ${config.title}`}>
          {title}
        </h3>
        {subtitle && (
          <p className={`text-steel ${config.subtitle}`}>
            {subtitle}
          </p>
        )}
      </div>

      {/* Progress Steps */}
      {showProgress && progressSteps.length > 0 && (
        <div className="w-full max-w-md space-y-3">
          <div className="flex items-center justify-between text-sm">
            <span className="text-steel">Progress</span>
            <span className="text-accent font-mono">
              {currentStep + 1}/{progressSteps.length}
            </span>
          </div>

          <div className="w-full bg-surface-3 rounded-full h-1.5">
            <div
              className="bg-accent rounded-full h-1.5 transition-all duration-500"
              style={{ width: `${((currentStep + 1) / progressSteps.length) * 100}%` }}
            />
          </div>

          <div className="space-y-2">
            {progressSteps.map((step, index) => (
              <div key={index} className="flex items-center space-x-3">
                <div className={`w-1.5 h-1.5 rounded-full ${
                  index <= currentStep
                    ? 'bg-accent animate-pulse'
                    : 'bg-surface-3'
                }`} />
                <span className={`text-sm ${
                  index <= currentStep ? 'text-ivory' : 'text-steel/60'
                }`}>
                  {step}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Live Data Indicators */}
      {showLiveIndicators && (
        <div className="flex flex-wrap justify-center gap-4 mt-6">
          <LiveDataIndicator
            label="ORACLE"
            value="SYNCING"
            status="loading"
            compact={true}
          />
          <LiveDataIndicator
            label="NETWORK"
            value="CONNECTED"
            status="live"
            compact={true}
          />
          <LiveDataIndicator
            label="PRICES"
            value="UPDATING"
            status="loading"
            compact={true}
          />
        </div>
      )}

      {/* Professional Footer */}
      <div className="text-xs text-steel/60 text-center mt-4">
        <div>LEVER Protocol • Professional DeFi Infrastructure</div>
        <div className="mt-1">Powered by Base • Audited Smart Contracts</div>
      </div>
    </div>
  );
};

export default ProfessionalLoader;