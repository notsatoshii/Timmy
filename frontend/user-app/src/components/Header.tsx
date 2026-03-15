import React from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';

const Header: React.FC = () => {
  return (
    <header className="bg-white shadow-sm border-b border-gray-200">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center py-4">
          {/* Logo and Title */}
          <div className="flex items-center space-x-3">
            <div className="flex-shrink-0">
              <h1 className="text-2xl font-bold text-primary-600">LEVER</h1>
            </div>
            <div className="hidden sm:block">
              <p className="text-sm text-gray-600">Synthetic Leveraged Perpetuals</p>
              <p className="text-xs text-gray-400">Base Sepolia Testnet</p>
            </div>
          </div>

          {/* Connection Status and Actions */}
          <div className="flex items-center space-x-4">
            <div className="hidden lg:flex items-center space-x-6">
              <div className="text-right">
                <p className="text-sm font-medium text-gray-900">
                  Prediction Market Leverage
                </p>
                <p className="text-xs text-gray-600">
                  Binary outcomes • Up to 30x leverage
                </p>
              </div>
            </div>

            <ConnectButton />
          </div>
        </div>
      </div>
    </header>
  );
};

export default Header;