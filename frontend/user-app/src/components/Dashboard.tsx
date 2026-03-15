import React, { useState } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount } from 'wagmi';
import Header from './Header';
import Markets from './Markets';
import Trading from './Trading';
import Vault from './Vault';
import Positions from './Positions';

type TabType = 'markets' | 'trading' | 'vault' | 'positions';

const Dashboard: React.FC = () => {
  const [activeTab, setActiveTab] = useState<TabType>('markets');
  const { isConnected } = useAccount();

  const tabs = [
    { id: 'markets' as TabType, label: 'Markets', description: 'Browse prediction markets' },
    { id: 'trading' as TabType, label: 'Trading', description: 'Open/close positions' },
    { id: 'vault' as TabType, label: 'Vault', description: 'LP deposits & yields' },
    { id: 'positions' as TabType, label: 'Positions', description: 'Your active positions' },
  ];

  const renderContent = () => {
    switch (activeTab) {
      case 'markets':
        return <Markets />;
      case 'trading':
        return <Trading />;
      case 'vault':
        return <Vault />;
      case 'positions':
        return <Positions />;
      default:
        return <Markets />;
    }
  };

  return (
    <div className="min-h-screen bg-gray-50">
      <Header />

      {/* Navigation Tabs */}
      <div className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex space-x-8">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`py-4 px-1 border-b-2 font-medium text-sm transition-colors duration-200 ${
                  activeTab === tab.id
                    ? 'border-primary-500 text-primary-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                <div className="flex flex-col items-center">
                  <span>{tab.label}</span>
                  <span className="text-xs opacity-60">{tab.description}</span>
                </div>
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {!isConnected ? (
          <div className="text-center py-12">
            <h3 className="text-lg font-medium text-gray-900 mb-4">
              Connect your wallet to start trading
            </h3>
            <p className="text-gray-600 mb-8">
              Connect to Base Sepolia testnet to access LEVER Protocol
            </p>
            <ConnectButton />
          </div>
        ) : (
          renderContent()
        )}
      </main>
    </div>
  );
};

export default Dashboard;