import React, { useState, useCallback, lazy, Suspense } from 'react';
import { useWallet } from '../hooks/useWallet';
import { usePageTitle } from '../hooks/usePageTitle';
import ConnectWallet from './ConnectWallet';
import Header from './Header';
import ProtocolStats from './ProtocolStats';
import Markets from './Markets';
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

// Lazy load heavy components
const Trading = lazy(() => import('./Trading'));
const VaultOptimized = lazy(() => import('./VaultOptimized'));
const Positions = lazy(() => import('./Positions'));

type TabType = 'markets' | 'trading' | 'vault' | 'positions' | 'marketdetail' | 'roadmap';

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

  // Dynamic page title based on current section
  const currentSection = selectedMarket ? 'market-detail' : activeTab;
  const customTitle = selectedMarket ? `${selectedMarket.description}` : undefined;
  usePageTitle(currentSection as any, customTitle);

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
    { id: 'marketdetail' as TabType, label: 'Market Detail', description: 'SpaceX IPO market analysis' },
    { id: 'roadmap' as TabType, label: 'Roadmap', description: 'Mainnet deployment plan' },
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
            <Suspense fallback={<ComponentLoader title="Trading Interface" />}>
              <Trading selectedTrade={selectedTrade} />
            </Suspense>
          </ErrorBoundary>
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
              <Positions />
            </Suspense>
          </ErrorBoundary>
        );
      case 'marketdetail':
        const spaceXMarket = {
          id: 'demo-1',
          description: 'Largest IPO by Market Cap 2026: SpaceX?',
          price: 0.54,
          resolutionTime: new Date('2026-12-30').getTime(),
          category: 'Technology',
          isLive: true,
        };
        return (
          <ErrorBoundary panelName="MarketDetail">
            <LazyMarketDetail
              market={spaceXMarket}
              onBack={() => setActiveTab('markets')}
              onTradeSelect={handleTradeSelection}
            />
          </ErrorBoundary>
        );
      case 'roadmap':
        return (
          <ErrorBoundary panelName="Roadmap">
            <MainnetRoadmap />
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
      {/* Testnet Banner - Most prominent position */}
      <ErrorBoundary panelName="TestnetBanner">
        <TestnetBanner />
      </ErrorBoundary>

      <ErrorBoundary panelName="Header">
        <Header />
      </ErrorBoundary>

      {/* Institutional Status Header */}
      <ErrorBoundary panelName="InstitutionalHeader">
        <InstitutionalHeader />
      </ErrorBoundary>

      {/* Protocol Stats Banner - Always visible, minimal performance impact */}
      <ErrorBoundary panelName="ProtocolStats">
        <ProtocolStats />
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

      {/* Professional Status Bar */}
      <ErrorBoundary panelName="ProfessionalStatusBar">
        <ProfessionalStatusBar showDetailed={true} />
      </ErrorBoundary>

      {/* Professional Footer */}
      <Footer />
    </div>
  );
};

export default DashboardOptimized;