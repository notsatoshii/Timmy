import React from 'react';
import { WagmiProvider } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { config } from './config/wagmi';
import Dashboard from './components/Dashboard';
import ErrorBoundary from './components/ErrorBoundary';

const queryClient = new QueryClient();

function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <div className="min-h-screen bg-gray-50">
          <ErrorBoundary panelName="Application">
            <Dashboard />
          </ErrorBoundary>
        </div>
      </QueryClientProvider>
    </WagmiProvider>
  );
}

export default App;
