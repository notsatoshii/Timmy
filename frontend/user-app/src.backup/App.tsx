import React, { useState, useEffect } from 'react';
import { WagmiProvider } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import DashboardOptimized from './components/DashboardOptimized';
import ErrorBoundary from './components/ErrorBoundary';
import MonitoringDashboard from './components/MonitoringDashboard';
import { NotificationProvider } from './contexts/NotificationContext';
import { DemoProvider } from './contexts/DemoContext';
import { AnalyticsProvider } from './contexts/AnalyticsContext';
import { config } from './config/wagmi';
import { analytics } from './services/analytics';
import { errorMonitoring } from './services/errorMonitoring';
import { healthCheck } from './services/healthCheck';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30000,
      gcTime: 300000,
      refetchOnWindowFocus: false,
      retry: false,
    },
  },
});

function App() {
  const [showMonitoring, setShowMonitoring] = useState(false);

  useEffect(() => {
    // Initialize monitoring services
    console.log('[App] Initializing production monitoring...');

    // Track app initialization
    analytics.trackPerformance({
      metric: 'TTFB',
      value: performance.now(),
      rating: 'good'
    });

    // Add keyboard shortcut to open monitoring dashboard (development only)
    if (process.env.NODE_ENV === 'development') {
      const handleKeyPress = (e: KeyboardEvent) => {
        // Ctrl+Shift+M to open monitoring
        if (e.ctrlKey && e.shiftKey && e.key === 'M') {
          e.preventDefault();
          setShowMonitoring(prev => !prev);
        }
      };

      window.addEventListener('keydown', handleKeyPress);
      console.log('[App] Press Ctrl+Shift+M to open monitoring dashboard');

      return () => window.removeEventListener('keydown', handleKeyPress);
    }
  }, []);

  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <DemoProvider>
          <NotificationProvider>
            <AnalyticsProvider>
              <div className="min-h-screen bg-surface-0">
                <ErrorBoundary panelName="Application">
                  <DashboardOptimized />
                </ErrorBoundary>

                {/* Monitoring Dashboard (development only) */}
                {process.env.NODE_ENV === 'development' && (
                  <MonitoringDashboard
                    isVisible={showMonitoring}
                    onClose={() => setShowMonitoring(false)}
                  />
                )}
              </div>
            </AnalyticsProvider>
          </NotificationProvider>
        </DemoProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}

export default App;
