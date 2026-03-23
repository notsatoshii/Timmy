import React, { useState, useCallback, lazy, Suspense } from 'react';
import { useWallet } from '../hooks/useWallet';
import { usePageTitle } from '../hooks/usePageTitle';
import ConnectWallet from './ConnectWallet';
import Header from './Header';
import ProtocolStats from './ProtocolStats';
import LazyMarketDetail from './LazyMarketDetail';
import MainnetRoadmap from './MainnetRoadmap';
import ErrorBoundary from './ErrorBoundary';
import Skeleton from './Skeleton';
import LeverLoader from './LeverLoader';
import ProfessionalLoader from './ProfessionalLoader';
import TestnetBanner from './TestnetBanner';
import Footer from './Footer';
import InstitutionalHeader from './InstitutionalHeader';
import ProfessionalStatusBar from './ProfessionalStatusBar';

// Lazy load heavy components — consistent ProfessionalLoader on all tabs
const Markets = lazy(() => import('./Markets'));
const Trading = lazy(() => import('./Trading'));
const VaultOptimized = lazy(() => import('./VaultOptimized'));
const Positions = lazy(() => import('./Positions'));

type TabType = 'markets' | 'vault' | 'positions';

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
  const [positionStats, setPositionStats] = useState<{
    netPnl: string;
    totalEquity: string;
    lockedCollateral: string;
    activePositions: number;
  } | undefined>(undefined);
  const { isConnected } = useWallet();

  // Dynamic page title based on current section
  const currentSection = selectedMarket ? 'market-detail' : activeTab;
  const customTitle = selectedMarket ? `${selectedMarket.description}` : undefined;
  usePageTitle(currentSection as any, customTitle);

  const handleMarketDetail = useCallback((market: Market) => {
    setSelectedMarket(market);
  }, []);

  const handleBackToMarkets = useCallback(() => {
    setSelectedMarket(null);
  }, []);

  const handleTabChange = useCallback((tabId: TabType) => {
    // Clear market detail and trade selection when changing tabs
    if (tabId !== 'markets') {
      setSelectedMarket(null);
      setSelectedTrade(null);
    }
    setActiveTab(tabId);
  }, []);

  const tabs = [
    { id: 'markets' as TabType, label: 'Trade', description: 'Browse markets & open positions' },
    { id: 'vault' as TabType, label: 'Vault', description: 'LP deposits & yields' },
    { id: 'positions' as TabType, label: 'Positions', description: 'Your active positions' },
  ];

  // Enhanced Professional Loading Component
  const ComponentLoader: React.FC<{
    title: string;
    variant?: 'default' | 'data' | 'blockchain' | 'trading';
    showProgress?: boolean;
  }> = ({ title, variant = 'default', showProgress = false }) => {
    const getVariantAndSubtitle = () => {
      switch (title) {
        case 'Trading Interface':
          return {
            variant: 'trading' as const,
            subtitle: 'Connecting to execution engine and price feeds',
            showLiveIndicators: true,
            progressSteps: ['Loading markets', 'Connecting wallet', 'Fetching prices', 'Ready to trade']
          };
        case 'Liquidity Vault':
          return {
            variant: 'data' as const,
            subtitle: 'Loading LP positions and yield data',
            showLiveIndicators: true,
            progressSteps: ['Loading vault state', 'Fetching APY data', 'Calculating yields']
          };
        case 'Your Positions':
          return {
            variant: 'blockchain' as const,
            subtitle: 'Fetching position data from smart contracts',
            showLiveIndicators: true,
            progressSteps: ['Querying positions', 'Calculating PnL', 'Loading history']
          };
        case 'Prediction Markets':
          return {
            variant: 'default' as const,
            subtitle: 'Loading markets and oracle price feeds',
            showLiveIndicators: true,
            progressSteps: ['Fetching markets', 'Loading prices', 'Ready']
          };
        default:
          return {
            variant: variant,
            subtitle: 'Please wait while we load the interface',
            showLiveIndicators: false,
            progressSteps: []
          };
      }
    };

    const config = getVariantAndSubtitle();

    return (
      <ProfessionalLoader
        title={`Loading ${title}`}
        subtitle={config.subtitle}
        variant={config.variant}
        size="lg"
        showLiveIndicators={config.showLiveIndicators}
        showProgress={showProgress}
        progressSteps={config.progressSteps}
        currentStep={1} // Simulate progress
      />
    );
  };

  // Handle trade selection without navigating away — keeps markets visible
  const handleTradeSelectionFused = useCallback((marketId: string, marketName: string, direction: 'long' | 'short') => {
    setSelectedTrade({ marketId, marketName, direction });
    setSelectedMarket(null);
  }, []);

  const handleClearTrade = useCallback(() => {
    setSelectedTrade(null);
  }, []);

  const renderContent = () => {
    switch (activeTab) {
      case 'markets':
        if (selectedMarket) {
          return (
            <ErrorBoundary panelName="MarketDetail">
              <LazyMarketDetail
                market={selectedMarket}
                onBack={handleBackToMarkets}
                onTradeSelect={handleTradeSelectionFused}
              />
            </ErrorBoundary>
          );
        }
        return (
          <div className="flex flex-col lg:flex-row gap-6">
            {/* Markets grid — shrinks when trade panel is open */}
            <div className={selectedTrade ? 'lg:w-3/5 xl:w-2/3' : 'w-full'}>
              <ErrorBoundary panelName="Markets">
                <Suspense fallback={<ComponentLoader title="Prediction Markets" />}>
                  <Markets
                    onTradeSelect={handleTradeSelectionFused}
                    onMarketDetail={handleMarketDetail}
                  />
                </Suspense>
              </ErrorBoundary>
            </div>

            {/* Trade panel — slides in from right when a market is selected */}
            {selectedTrade && (
              <div className="lg:w-2/5 xl:w-1/3 lg:sticky lg:top-4 lg:self-start">
                <ErrorBoundary panelName="Trading">
                  <Suspense fallback={<ComponentLoader title="Trading Interface" />}>
                    <div className="relative">
                      <button
                        onClick={handleClearTrade}
                        className="absolute -top-1 -right-1 z-10 w-7 h-7 flex items-center justify-center rounded-full bg-surface-3 border border-border text-steel hover:text-ivory hover:border-border-light transition-colors text-sm"
                        title="Close trade panel"
                      >
                        ✕
                      </button>
                      <Trading selectedTrade={selectedTrade} />
                    </div>
                  </Suspense>
                </ErrorBoundary>
              </div>
            )}
          </div>
        );
      case 'vault':
        return (
          <ErrorBoundary panelName="Vault">
            <Suspense fallback={<ComponentLoader title="Liquidity Vault" />}>
              <VaultOptimized />
            </Suspense>
          </ErrorBoundary>
        );
      case 'positions':
        return (
          <ErrorBoundary panelName="Positions">
            <Suspense fallback={<ComponentLoader title="Your Positions" />}>
              <Positions onStatsUpdate={setPositionStats} />
            </Suspense>
          </ErrorBoundary>
        );
      default:
        return (
          <ErrorBoundary panelName="Markets">
            <Suspense fallback={<ComponentLoader title="Prediction Markets" />}>
              <Markets
                onTradeSelect={handleTradeSelectionFused}
                onMarketDetail={handleMarketDetail}
              />
            </Suspense>
          </ErrorBoundary>
        );
    }
  };

  return (
    <div className="min-h-screen bg-surface-0 overflow-x-hidden">

      <ErrorBoundary panelName="Header">
        <Header />
      </ErrorBoundary>

      {/* Protocol Stats Banner - Always visible, minimal performance impact */}
      <ErrorBoundary panelName="ProtocolStats">
        <ProtocolStats activeTab={activeTab} positionStats={positionStats} />
      </ErrorBoundary>

      {/* Navigation Tabs — Neumorphic pill switcher */}
      <div className="border-b border-border">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3">
          <div className="lever-inset p-1 flex">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => handleTabChange(tab.id)}
                className={`flex-1 py-2.5 px-4 rounded-lg font-medium text-sm transition-all duration-200 ${
                  activeTab === tab.id
                    ? 'bg-surface-2 text-accent shadow-raised font-semibold'
                    : 'text-steel hover:text-ivory'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {renderContent()}

        {/* Show wallet connection prompt for positions tab when not connected */}
        {!isConnected && activeTab === 'positions' && (
          <div className="fixed bottom-4 right-4 bg-surface-2 border border-border rounded-lg shadow-card p-4 max-w-sm z-50">
            <h4 className="font-medium text-gray-100 mb-2">Connect to Trade</h4>
            <p className="text-sm text-gray-400 mb-3">
              Connect your wallet to open positions and manage trades
            </p>
            <ConnectWallet />
          </div>
        )}
      </main>

      {/* Professional Status Bar */}
      <ErrorBoundary panelName="ProfessionalStatusBar">
        <ProfessionalStatusBar />
      </ErrorBoundary>

      {/* Professional Footer */}
      {/* removed */}
    </div>
  );
};

export default DashboardOptimized;