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

// Enhanced transport with fallback and retry logic
const baseSepoliaTransport = fallback(
  baseSepoliaRPCs.map((url) =>
    http(url, {
      batch: true,
      timeout: 10000, // 10 second timeout
      retryCount: 3,
      retryDelay: 2000, // 2 second base retry delay
    })
  ),
  {
    rank: {
      interval: 60000, // Check RPC health every minute
      sampleCount: 5,
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
    multicall: true,
  },
});

export { baseSepolia };
