import React, { useState, useCallback, lazy, Suspense } from 'react';
import { useWallet } from '../hooks/useWallet';
import ConnectWallet from './ConnectWallet';
import Header from './Header';
import ProtocolStats from './ProtocolStats';
import Markets from './Markets';
import LazyMarketDetail from './LazyMarketDetail';
import ErrorBoundary from './ErrorBoundary';
import Skeleton from './Skeleton';

// Lazy load heavy components
const Trading = lazy(() => import('./Trading'));
const VaultOptimized = lazy(() => import('./VaultOptimized'));
const Positions = lazy(() => import('./Positions'));

type TabType = 'markets' | 'trading' | 'vault' | 'positions';

interface Market {
  id: string;
  description: string;
  price: number;
  resolutionTime: number;
  category: string;
  isLive: boolean;
}

const DashboardOptimized: React.FC = () => {
  const [activeTab, setActiveTab] = useState<TabType>('markets');
  const [selectedTrade, setSelectedTrade] = useState<{
    marketId: string;
    marketName: string;
    direction: 'long' | 'short';
  } | null>(null);
  const [selectedMarket, setSelectedMarket] = useState<Market | null>(null);
  const { isConnected } = useWallet();

  const handleTradeSelection = useCallback((marketId: string, marketName: string, direction: 'long' | 'short') => {
    setSelectedTrade({ marketId, marketName, direction });
    setSelectedMarket(null); // Clear market detail view
    setActiveTab('trading');
  }, []);

  const handleMarketDetail = useCallback((market: Market) => {
    setSelectedMarket(market);
  }, []);

  const handleBackToMarkets = useCallback(() => {
    setSelectedMarket(null);
  }, []);

  const handleTabChange = useCallback((tabId: TabType) => {
    // Clear market detail when changing tabs
    if (tabId !== 'markets') {
      setSelectedMarket(null);
    }
    setActiveTab(tabId);
  }, []);

  const tabs = [
    { id: 'markets' as TabType, label: 'Markets', description: 'Browse prediction markets' },
    { id: 'trading' as TabType, label: 'Trading', description: 'Open/close positions' },
    { id: 'vault' as TabType, label: 'Vault', description: 'LP deposits & yields' },
    { id: 'positions' as TabType, label: 'Positions', description: 'Your active positions' },
  ];

  // Loading skeleton for heavy components
  const ComponentSkeleton: React.FC<{ title: string }> = ({ title }) => (
    <div className="space-y-6">
      <div>
        <Skeleton height="32px" width="200px" className="mb-2" />
        <Skeleton height="20px" width="400px" />
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {[1, 2, 3].map((index) => (
          <div key={index} className="bg-surface-1 rounded-lg border border-border p-6">
            <Skeleton height="20px" width="120px" className="mb-3" />
            <Skeleton height="28px" width="80px" className="mb-2" />
            <Skeleton height="16px" width="200px" />
          </div>
        ))}
      </div>
    </div>
  );

  const renderContent = () => {
    switch (activeTab) {
      case 'markets':
        if (selectedMarket) {
          return (
            <ErrorBoundary panelName="MarketDetail">
              <LazyMarketDetail
                market={selectedMarket}
                onBack={handleBackToMarkets}
                onTradeSelect={handleTradeSelection}
              />
            </ErrorBoundary>
          );
        }
        return (
          <ErrorBoundary panelName="Markets">
            <Markets
              onTradeSelect={handleTradeSelection}
              onMarketDetail={handleMarketDetail}
            />
          </ErrorBoundary>
        );
      case 'trading':
        return (
          <ErrorBoundary panelName="Trading">
            <Suspense fallback={<ComponentSkeleton title="Trading Interface" />}>
              <Trading selectedTrade={selectedTrade} />
            </Suspense>
          </ErrorBoundary>
        );
      case 'vault':
        return (
          <ErrorBoundary panelName="Vault">
            <Suspense fallback={<ComponentSkeleton title="Liquidity Vault" />}>
              <VaultOptimized />
            </Suspense>
          </ErrorBoundary>
        );
      case 'positions':
        return (
          <ErrorBoundary panelName="Positions">
            <Suspense fallback={<ComponentSkeleton title="Your Positions" />}>
              <Positions />
            </Suspense>
          </ErrorBoundary>
        );
      default:
        return (
          <ErrorBoundary panelName="Markets">
            <Markets
              onTradeSelect={handleTradeSelection}
              onMarketDetail={handleMarketDetail}
            />
          </ErrorBoundary>
        );
    }
  };

  return (
    <div className="min-h-screen bg-surface-0">
      <ErrorBoundary panelName="Header">
        <Header />
      </ErrorBoundary>

      {/* Protocol Stats Banner - Always visible, minimal performance impact */}
      <ErrorBoundary panelName="ProtocolStats">
        <ProtocolStats />
      </ErrorBoundary>

      {/* Navigation Tabs */}
      <div className="bg-surface-1 border-b border-border">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          {/* Desktop navigation */}
          <div className="hidden md:flex space-x-8">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => handleTabChange(tab.id)}
                className={`py-4 px-1 border-b-2 font-medium text-sm transition-colors duration-200 ${
                  activeTab === tab.id
                    ? 'border-accent text-accent'
                    : 'border-transparent text-gray-500 hover:text-gray-300 hover:border-border-light'
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
                  onClick={() => handleTabChange(tab.id)}
                  className={`py-3 px-1 border-b-2 font-medium text-xs transition-colors duration-200 ${
                    activeTab === tab.id
                      ? 'border-accent text-accent'
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
        {renderContent()}

        {/* Show wallet connection prompt only for transaction-heavy tabs when not connected */}
        {!isConnected && (activeTab === 'trading' || activeTab === 'positions') && (
          <div className="fixed bottom-4 right-4 bg-surface-2 border border-border rounded-lg shadow-card p-4 max-w-sm z-50">
            <h4 className="font-medium text-gray-100 mb-2">Connect to Trade</h4>
            <p className="text-sm text-gray-400 mb-3">
              Connect your wallet to open positions and manage trades
            </p>
            <ConnectWallet />
          </div>
        )}
      </main>
    </div>
  );
};

export default DashboardOptimized;