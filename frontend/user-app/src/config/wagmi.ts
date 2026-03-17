import { createConfig, http, fallback } from 'wagmi';
import { baseSepolia } from 'wagmi/chains';
import { injected } from 'wagmi/connectors';

// Multiple RPC endpoints for redundancy and rate limit handling
const baseSepoliaRPCs = [
  'https://sepolia.base.org', // Primary Base Sepolia RPC
  'https://base-sepolia-rpc.publicnode.com', // Public node backup
  'https://base-sepolia.blockpi.network/v1/rpc/public', // BlockPI backup
  'https://sepolia.base.org/v1/rpc', // Alternative base endpoint
];

// Enhanced transport with fallback, reduced batch size, and aggressive 413 handling
const baseSepoliaTransport = fallback(
  baseSepoliaRPCs.map((url, index) =>
    http(url, {
      batch: {
        multicall: {
          batchSize: index === 0 ? 8 : 4, // Smaller batch sizes to avoid 413 errors
          wait: 100, // Increased batching wait time
        }
      },
      timeout: 15000, // Increased timeout for slower responses under rate limiting
      retryCount: 2, // Reduced retries to avoid hammering rate-limited RPCs
      retryDelay: (config) => {
        // Exponential backoff with longer delays for rate limiting
        const attempt = config.count;
        const isRateLimit = config.error && (
          config.error.message?.includes('413') ||
          config.error.message?.includes('429') ||
          config.error.message?.includes('rate limit') ||
          config.error.message?.includes('too many requests')
        );

        if (isRateLimit) {
          // Much longer delays for rate limiting
          return Math.min(5000 * Math.pow(2, attempt), 60000);
        }

        // Normal exponential backoff for other errors
        return Math.min(1000 * Math.pow(2, attempt), 10000);
      },
    })
  ),
  {
    rank: {
      interval: 30000, // More frequent RPC health checks
      sampleCount: 3,
      targetCount: 2, // Try to keep 2 healthy RPCs
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
