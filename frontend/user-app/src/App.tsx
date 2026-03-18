import React from 'react';
import { WagmiProvider } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import DashboardOptimized from './components/DashboardOptimized';
import ErrorBoundary from './components/ErrorBoundary';
import { NotificationProvider } from './contexts/NotificationContext';
import { DemoProvider } from './contexts/DemoContext';
import { config } from './config/wagmi';

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
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <DemoProvider>
          <NotificationProvider>
            <div className="min-h-screen bg-surface-0">
              <ErrorBoundary panelName="Application">
                <DashboardOptimized />
              </ErrorBoundary>
            </div>
          </NotificationProvider>
        </DemoProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}

export default App;
