import React from 'react';
import { WagmiProvider, createConfig, http } from 'wagmi';
import { baseSepolia } from 'wagmi/chains';
import { injected } from 'wagmi/connectors';
import { privateKeyToAccount } from 'viem/accounts';
import { createWalletClient } from 'viem';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import DashboardOptimized from './components/DashboardOptimized';
import ErrorBoundary from './components/ErrorBoundary';
import { NotificationProvider } from './contexts/NotificationContext';
import { DemoProvider } from './contexts/DemoContext';
import { isDemoMode, TEST_WALLET_KEY } from './connectors/demo';

// Create demo wallet client for demo mode transactions
const createDemoWalletClient = () => {
  const account = privateKeyToAccount(`0x${TEST_WALLET_KEY}` as `0x${string}`);
  return createWalletClient({
    account,
    chain: baseSepolia,
    transport: http(),
  });
};

// Configure wagmi with demo mode support
const config = createConfig({
  chains: [baseSepolia],
  connectors: [injected()],
  transports: {
    [baseSepolia.id]: http(),
  },
  // Add demo wallet client for demo mode
  ...(isDemoMode() && {
    client: createDemoWalletClient,
  }),
});

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
            <div className="min-h-screen bg-gray-50">
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
