// Simple React component to test useVaultMulticall hook
import React from 'react';
import { createRoot } from 'react-dom/client';
import { WagmiProvider } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { http, createConfig } from 'wagmi';
import { baseSepolia } from 'wagmi/chains';
import { useVaultMulticall } from './src/hooks/useVaultMulticall';
import { useMemoizedVaultCalculations } from './src/hooks/useMemoizedCalculations';

// Wagmi config
const config = createConfig({
  chains: [baseSepolia],
  transports: {
    [baseSepolia.id]: http('https://sepolia.base.org'),
  },
});

const queryClient = new QueryClient();

function VaultDebugger() {
  const vaultData = useVaultMulticall();

  const metrics = useMemoizedVaultCalculations({
    totalAssets: vaultData.totalAssets,
    totalSupply: vaultData.totalSupply,
    borrowFees: BigInt(0),
    transactionFees: BigInt(0),
    liquidationFees: BigInt(0),
    settlementFees: BigInt(0),
    globalOI: vaultData.globalOI,
    userShares: vaultData.userShares,
    usdtBalance: vaultData.usdtBalance,
  });

  console.log('=== VAULT DEBUGGER ===', {
    vaultData,
    metrics,
  });

  return (
    <div style={{ padding: '20px', fontFamily: 'monospace' }}>
      <h2>Vault Data Debugger</h2>

      <h3>Raw Vault Data</h3>
      <pre>{JSON.stringify({
        totalAssets: vaultData.totalAssets?.toString(),
        totalSupply: vaultData.totalSupply?.toString(),
        sharePrice: vaultData.sharePrice?.toString(),
        globalOI: vaultData.globalOI?.toString(),
        isLoading: vaultData.isLoadingVaultData,
        hasError: vaultData.hasError,
        errors: vaultData.errors?.map(e => e.message),
      }, null, 2)}</pre>

      <h3>Calculated Metrics</h3>
      <pre>{JSON.stringify({
        tvl: metrics.tvl,
        sharePrice: metrics.sharePrice,
        utilization: metrics.utilization,
        annualizedAPY: metrics.annualizedAPY,
      }, null, 2)}</pre>

      <h3>Display Values</h3>
      <div>
        <div><strong>TVL:</strong> ${metrics.tvl.toLocaleString()}</div>
        <div><strong>Share Price:</strong> ${metrics.sharePrice.toFixed(4)}</div>
        <div><strong>Utilization:</strong> {metrics.utilization.toFixed(2)}%</div>
        <div><strong>APY:</strong> {metrics.annualizedAPY.toFixed(2)}%</div>
      </div>
    </div>
  );
}

function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <VaultDebugger />
      </QueryClientProvider>
    </WagmiProvider>
  );
}

// Mount the component
const container = document.getElementById('root') || document.body;
const root = createRoot(container);
root.render(<App />);

export default App;