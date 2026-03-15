import React from 'react';
import { WagmiProvider } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { config } from './config/wagmi';
import DashboardOptimized from './components/DashboardOptimized';
import ErrorBoundary from './components/ErrorBoundary';
import { NotificationProvider } from './contexts/NotificationContext';

// Optimized QueryClient configuration for better performance
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30000, // 30 seconds - prevent unnecessary refetches
      gcTime: 300000, // 5 minutes - keep data in cache longer
      refetchOnWindowFocus: false, // Reduce unnecessary network calls
      refetchOnMount: true, // Ensure fresh data on component mount
      retry: (failureCount, error: any) => {
        // Only retry network errors, not contract errors
        if (failureCount < 2 && error?.message?.includes('network')) {
          return true;
        }
        return false;
      },
    },
  },
});

function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <NotificationProvider>
          <div className="min-h-screen bg-gray-50">
            <ErrorBoundary panelName="Application">
              <DashboardOptimized />
            </ErrorBoundary>
          </div>
        </NotificationProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}

export default App;
