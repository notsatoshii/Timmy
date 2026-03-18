import React from 'react';
import { useWallet } from '../hooks/useWallet';
import ConnectWallet from './ConnectWallet';
import ConnectionStatus, { NetworkIndicator } from './ConnectionStatus';

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

      <header className="border-b border-border bg-surface-1/30 backdrop-blur-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-4">
            {/* Enhanced Logo Section */}
            <div className="flex items-center space-x-4">
              <div className="flex items-center space-x-3">
                <div className="flex-shrink-0 relative">
                  <img
                    src="/lever-logo.svg"
                    alt="LEVER Protocol"
                    className="h-10"
                    style={{ filter: 'drop-shadow(0 0 16px rgba(230,255,43,0.25))' }}
                  />
                  <div className="absolute -inset-1 bg-gradient-to-r from-accent/20 to-teal/10 rounded-lg blur opacity-30" />
                </div>
                <div className="hidden sm:block">
                  <div className="flex items-center space-x-2">
                    <h1 className="text-ivory font-display font-bold text-lg tracking-tight">
                      LEVER
                    </h1>
                    <span className="text-steel text-sm font-medium">Protocol</span>
                  </div>
                  <p className="text-xs font-medium text-steel">
                    Synthetic Leveraged Perpetuals
                  </p>
                </div>
              </div>

              {/* Network & Connection Status */}
              <div className="hidden md:flex items-center space-x-4 pl-4 border-l border-border/50">
                <ConnectionStatus className="text-xs" />
                <div className="h-4 w-px bg-border" />
                <NetworkIndicator />
              </div>
            </div>

            {/* Right side - Enhanced with status indicators */}
            <div className="flex items-center space-x-4">
              {/* Product highlights */}
              <div className="hidden xl:block text-right">
                <p className="text-sm font-semibold text-ivory">
                  Prediction Market Leverage
                </p>
                <div className="flex items-center space-x-2 justify-end">
                  <p className="text-xs text-steel">
                    Binary outcomes · Up to <span className="text-accent font-bold">12x</span> leverage
                  </p>
                  <div className="w-1 h-1 bg-accent rounded-full opacity-75" />
                  <span className="text-xs text-steel font-mono">v1.0.0-beta</span>
                </div>
              </div>

              {/* Wallet Connection */}
              <div className="flex items-center space-x-3">
                <ConnectWallet />
              </div>
            </div>
          </div>

          {/* Mobile status indicators */}
          <div className="md:hidden border-t border-border/30 pt-3 pb-2">
            <div className="flex items-center justify-between">
              <ConnectionStatus className="text-xs" showLabel={true} />
              <NetworkIndicator className="text-xs" />
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
