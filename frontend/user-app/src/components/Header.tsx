import React from 'react';
import { useWallet } from '../hooks/useWallet';
import ConnectWallet from './ConnectWallet';
import ConnectionStatus, { NetworkIndicator } from './ConnectionStatus';
import SecurityBadges from './SecurityBadges';
import LiveDataIndicator from './LiveDataIndicator';

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
                    className="h-12 lever-logo-glow"
                  />
                  <div className="absolute -inset-2 bg-gradient-to-r from-accent/10 to-teal/5 rounded-xl blur opacity-40" />
                </div>
                <div className="hidden sm:block">
                  <div className="flex items-center space-x-3">
                    <h1 className="lever-heading-lg font-display font-bold">
                      LEVER
                    </h1>
                    <span className="lever-caption text-accent bg-accent/10 px-2 py-0.5 rounded-md">
                      Protocol
                    </span>
                  </div>
                  <p className="lever-caption text-steel/90 mt-0.5">
                    Synthetic Leveraged Perpetuals
                  </p>
                  <div className="flex items-center space-x-2 mt-1">
                    <div className="w-1 h-1 bg-accent rounded-full animate-pulse" />
                    <span className="text-[10px] text-accent font-mono font-semibold">
                      INSTITUTIONAL GRADE
                    </span>
                  </div>
                </div>
              </div>

              {/* Enhanced Network & Connection Status with Professional Styling */}
              <div className="hidden md:flex items-center space-x-4 pl-4 border-l border-border/50">
                <div className="lever-status-live">
                  <ConnectionStatus className="text-xs" />
                </div>
                <div className="h-4 w-px bg-border/30" />
                <div className="lever-status-readonly">
                  <NetworkIndicator />
                </div>
              </div>
            </div>

            {/* Right side - Enhanced with status indicators */}
            <div className="flex items-center space-x-4">
              {/* Enhanced Product Highlights */}
              <div className="hidden xl:flex xl:flex-col xl:items-end xl:space-y-2">
                <div className="text-right">
                  <p className="lever-subtitle text-ivory">
                    Prediction Market Leverage
                  </p>
                  <div className="flex items-center space-x-3 justify-end mt-1">
                    <LiveDataIndicator
                      label="MAX LEV"
                      value="12x"
                      status="live"
                      compact={true}
                    />
                    <div className="w-px h-4 bg-border/50" />
                    <span className="lever-caption text-steel">v1.0.0-beta</span>
                  </div>
                </div>
                <SecurityBadges className="justify-end" />
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
