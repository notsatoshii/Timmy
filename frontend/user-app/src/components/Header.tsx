import React, { useState, useEffect } from 'react';
import { useWallet } from '../hooks/useWallet';
import ConnectWallet from './ConnectWallet';

const Header: React.FC = () => {
  const { isConnected } = useWallet();
  const [latency, setLatency] = useState<number | null>(null);

  useEffect(() => {
    const measureLatency = async () => {
      try {
        const start = performance.now();
        await fetch('https://sepolia.base.org', { method: 'HEAD', mode: 'no-cors' });
        const ms = Math.round(performance.now() - start);
        setLatency(ms);
      } catch {
        setLatency(null);
      }
    };
    measureLatency();
    const interval = setInterval(measureLatency, 30000);
    return () => clearInterval(interval);
  }, []);

  return (
    <header className="border-b border-border bg-surface-1/30 backdrop-blur-sm">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center py-4">
          <div className="flex items-center space-x-3">
            <img src="/lever-logo.png" alt="LEVER" className="h-10" />
          </div>
          <div className="flex items-center space-x-4">
            <div className="hidden sm:flex items-center space-x-2 text-xs text-steel">
              <span className={`w-1.5 h-1.5 rounded-full ${latency && latency < 500 ? 'bg-long' : 'bg-yellow-400'}`}></span>
              <span className="font-mono">{latency ? `${latency}ms` : '...'}</span>
              <span className="text-steel/50">Base Sepolia</span>
            </div>
            <ConnectWallet />
          </div>
        </div>
      </div>
    </header>
  );
};

export default Header;
