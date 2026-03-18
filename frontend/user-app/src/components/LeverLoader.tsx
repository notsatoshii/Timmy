import React from 'react';

interface LeverLoaderProps {
  message?: string;
  size?: 'sm' | 'md' | 'lg';
}

const LeverLoader: React.FC<LeverLoaderProps> = ({ message, size = 'md' }) => {
  const sizeMap = {
    sm: { icon: 32, text: 'text-xs' },
    md: { icon: 48, text: 'text-sm' },
    lg: { icon: 64, text: 'text-base' },
  };

  const { icon, text } = sizeMap[size];

  return (
    <div className="flex flex-col items-center justify-center py-16 space-y-4">
      <style>{`
        @keyframes lever-spin {
          0% { transform: rotate(0deg); }
          100% { transform: rotate(360deg); }
        }
        @keyframes lever-pulse-glow {
          0%, 100% { filter: drop-shadow(0 0 8px rgba(230,255,43,0.15)); }
          50% { filter: drop-shadow(0 0 20px rgba(230,255,43,0.4)); }
        }
        .lever-spin {
          animation: lever-spin 1.8s cubic-bezier(0.45, 0.05, 0.55, 0.95) infinite,
                     lever-pulse-glow 1.8s ease-in-out infinite;
        }
      `}</style>
      <div className="relative">
        <div
          className="absolute inset-0 rounded-full"
          style={{
            background: 'radial-gradient(circle, rgba(230,255,43,0.08) 0%, transparent 70%)',
            transform: 'scale(2.5)',
          }}
        />
        <img
          src="/lever-icon.png"
          alt="Loading"
          className="lever-spin relative"
          style={{ width: icon, height: icon }}
        />
      </div>
      {message && (
        <p className={`text-steel ${text} animate-pulse`}>{message}</p>
      )}
    </div>
  );
};

export default LeverLoader;
