import React, { useState } from 'react';
import { useAccount } from 'wagmi';
import ConnectWallet from './ConnectWallet';
import Header from './Header';
import Markets from './Markets';
import Trading from './Trading';
import Vault from './Vault';
import Positions from './Positions';
import ErrorBoundary from './ErrorBoundary';

type TabType = 'markets' | 'trading' | 'vault' | 'positions';

const Dashboard: React.FC = () => {
  const [activeTab, setActiveTab] = useState<TabType>('markets');
  const [selectedTrade, setSelectedTrade] = useState<{
    marketId: string;
    marketName: string;
    direction: 'long' | 'short';
  } | null>(null);
  const { isConnected } = useAccount();

  const handleTradeSelection = (marketId: string, marketName: string, direction: 'long' | 'short') => {
    setSelectedTrade({ marketId, marketName, direction });
    setActiveTab('trading');
  };

  const tabs = [
    { id: 'markets' as TabType, label: 'Markets', description: 'Browse prediction markets' },
    { id: 'trading' as TabType, label: 'Trading', description: 'Open/close positions' },
    { id: 'vault' as TabType, label: 'Vault', description: 'LP deposits & yields' },
    { id: 'positions' as TabType, label: 'Positions', description: 'Your active positions' },
  ];

  const renderContent = () => {
    switch (activeTab) {
      case 'markets':
        return (
          <ErrorBoundary panelName="Markets">
            <Markets onTradeSelect={handleTradeSelection} />
          </ErrorBoundary>
        );
      case 'trading':
        return (
          <ErrorBoundary panelName="Trading">
            <Trading selectedTrade={selectedTrade} />
          </ErrorBoundary>
        );
      case 'vault':
        return (
          <ErrorBoundary panelName="Vault">
            <Vault />
          </ErrorBoundary>
        );
      case 'positions':
        return (
          <ErrorBoundary panelName="Positions">
            <Positions />
          </ErrorBoundary>
        );
      default:
        return (
          <ErrorBoundary panelName="Markets">
            <Markets />
          </ErrorBoundary>
        );
    }
  };

  return (
    <div className="min-h-screen bg-gray-50">
      <ErrorBoundary panelName="Header">
        <Header />
      </ErrorBoundary>

      {/* Navigation Tabs */}
      <div className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          {/* Desktop navigation */}
          <div className="hidden md:flex space-x-8">
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

          {/* Mobile navigation */}
          <div className="md:hidden">
            <div className="grid grid-cols-4">
              {tabs.map((tab) => (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`py-3 px-1 border-b-2 font-medium text-xs transition-colors duration-200 ${
                    activeTab === tab.id
                      ? 'border-primary-500 text-primary-600'
                      : 'border-transparent text-gray-500'
                  }`}
                >
                  <div className="flex flex-col items-center space-y-1">
                    <span className="text-center leading-tight">{tab.label}</span>
                  </div>
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Always show content - wallet connection is handled by individual components */}
        {renderContent()}

        {/* Show wallet connection prompt only for transaction-heavy tabs when not connected */}
        {!isConnected && (activeTab === 'trading' || activeTab === 'positions') && (
          <div className="fixed bottom-4 right-4 bg-white border border-gray-200 rounded-lg shadow-lg p-4 max-w-sm">
            <h4 className="font-medium text-gray-900 mb-2">Connect to Trade</h4>
            <p className="text-sm text-gray-600 mb-3">
              Connect your wallet to open positions and manage trades
            </p>
            <ConnectWallet />
          </div>
        )}
      </main>
    </div>
  );
};

export default Dashboard;
