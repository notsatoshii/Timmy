import { createConfig, http, fallback } from 'wagmi';
import { baseSepolia } from 'wagmi/chains';
import { injected } from 'wagmi/connectors';

// Multiple RPC endpoints for redundancy and rate limit handling
const baseSepoliaRPCs = [
  'https://base-sepolia-rpc.publicnode.com', // CORS-friendly, most reliable
  'https://sepolia.base.org', // Base official fallback
];

// Enhanced transport with fallback, reduced batch size, and aggressive 413 handling
const baseSepoliaTransport = fallback(
  baseSepoliaRPCs.map((url, index) =>
    http(url, {
      batch: {
        batchSize: index === 0 ? 8 : 4, // Smaller batch sizes to avoid 413 errors
        wait: 100, // Increased batching wait time
      },
      timeout: 15000, // Increased timeout for slower responses under rate limiting
      retryCount: 2, // Reduced retries to avoid hammering rate-limited RPCs
      retryDelay: 3000, // Fixed delay between retries
    })
  ),
  {
    rank: {
      interval: 30000, // More frequent RPC health checks
      sampleCount: 3,
    },
  }
);

export const config = createConfig({
  chains: [baseSepolia],
  connectors: [
    injected(),
  ],
  transports: {
    [baseSepolia.id]: baseSepoliaTransport,
  },
  batch: {
    multicall: {
      batchSize: 6, // Conservative batch size to avoid 413 errors
      wait: 150, // Longer wait time to batch fewer frequent requests
    },
  },
});

export { baseSepolia };
