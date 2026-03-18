import React from 'react';
import { useWallet } from '../hooks/useWallet';
import ConnectWallet from './ConnectWallet';

const Header: React.FC = () => {
  const { isConnected } = useWallet();

  return (
    <>
      {/* Prominent Testnet Environment Banner */}
      <div className="bg-yellow-900/20 border-b border-yellow-600/30">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="py-2 text-center">
            <div className="flex items-center justify-center space-x-2">
              <div className="w-2 h-2 bg-yellow-400 rounded-full animate-pulse"></div>
              <span className="text-yellow-400 font-semibold text-sm uppercase tracking-wider">
                ⚠️ TESTNET ENVIRONMENT ⚠️
              </span>
              <div className="w-2 h-2 bg-yellow-400 rounded-full animate-pulse"></div>
            </div>
            <p className="text-yellow-200/80 text-xs mt-1">
              This is a demonstration on Base Sepolia testnet. Not real funds. Mainnet launch pending security audits.
            </p>
          </div>
        </div>
      </div>

      <header className="border-b border-border">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-4">
            {/* Logo */}
            <div className="flex items-center space-x-3">
              <div className="flex-shrink-0">
                <img
                  src="/lever-logo.png"
                  alt="LEVER"
                  className="h-8"
                  style={{ filter: 'drop-shadow(0 0 12px rgba(230,255,43,0.2))' }}
                />
              </div>
              <div className="hidden sm:block">
                <p className="text-xs font-medium text-steel">Synthetic Leveraged Perpetuals</p>
                <p className="text-[10px] text-steel/50 uppercase tracking-wider">Base Sepolia</p>
              </div>
            </div>

            {/* Right side */}
            <div className="flex items-center space-x-3">
              <div className="hidden lg:block text-right">
                <p className="text-xs font-medium text-ivory">Prediction Market Leverage</p>
                <p className="text-[10px] text-steel">
                  Binary outcomes · Up to <span className="text-accent font-semibold">12x</span> leverage
                </p>
              </div>
              <ConnectWallet />
            </div>
          </div>
        </div>
      </header>

      {/* Read-only notification */}
      {!isConnected && (
        <div className="border-b border-border bg-teal/5">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="py-2">
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-2">
                  <div className="w-1.5 h-1.5 bg-teal rounded-full"></div>
                  <p className="text-xs text-steel">
                    <span className="font-medium text-ivory">Read-only mode</span> — Browse markets & vault stats.
                    <span className="hidden sm:inline"> Connect wallet to trade.</span>
                  </p>
                </div>
                <p className="hidden sm:block text-[10px] text-steel/50">Live on Base Sepolia</p>
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  );
};

export default Header;
