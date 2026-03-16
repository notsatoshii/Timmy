import React, { useState } from 'react';
import { useAccount, useConnect, useDisconnect } from 'wagmi';
import { injected } from 'wagmi/connectors';
import { useDemo } from '../contexts/DemoContext';

const ConnectWallet: React.FC = () => {
  const { address, isConnected } = useAccount();
  const { connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const [isDemoConnecting, setIsDemoConnecting] = useState(false);
  const { isDemoMode, demoAddress } = useDemo();

  const connectDemo = async () => {
    try {
      setIsDemoConnecting(true);

      // For demo mode, we'll create a mock connection state
      // The test wallet address (derived from private key)
      const demoAddress = '0x742d35Cc6634C0532925a3b8D0a2dfABb3b9c8A0'; // Test wallet address

      // Set demo mode in localStorage to persist across reloads
      localStorage.setItem('demo-mode', 'true');
      localStorage.setItem('demo-address', demoAddress);

      // Refresh page to load in demo mode
      window.location.reload();

    } catch (error) {
      console.error('Demo connection failed:', error);
    } finally {
      setIsDemoConnecting(false);
    }
  };


  if (isPending || isDemoConnecting) {
    return (
      <div className="bg-accent hover:bg-accent-dim text-surface-0 font-semibold text-sm px-4 py-2 rounded-lg opacity-50">
        {isDemoConnecting ? 'Loading Demo...' : 'Connecting...'}
      </div>
    );
  }

  // Handle demo mode display
  if (isDemoMode && demoAddress) {
    const shortAddr = `${demoAddress.slice(0, 6)}...${demoAddress.slice(-4)}`;

    return (
      <div className="flex items-center space-x-2">
        <span className="text-sm font-mono text-gray-300 bg-surface-3 px-3 py-1.5 rounded-lg border border-purple-500">
          <span className="text-purple-400 mr-2">DEMO</span>
          {shortAddr}
        </span>
        <button
          onClick={() => {
            localStorage.removeItem('demo-mode');
            localStorage.removeItem('demo-address');
            window.location.reload();
          }}
          className="text-sm text-danger hover:text-danger-dim font-medium px-3 py-1.5 rounded-lg hover:bg-danger-muted transition-colors"
        >
          Exit Demo
        </button>
      </div>
    );
  }

  if (isConnected && address) {
    const shortAddr = `${address.slice(0, 6)}...${address.slice(-4)}`;

    return (
      <div className="flex items-center space-x-2">
        <span className="text-sm font-mono text-gray-300 bg-surface-3 px-3 py-1.5 rounded-lg border border-border">
          {shortAddr}
        </span>
        <button
          onClick={() => disconnect()}
          className="text-sm text-danger hover:text-danger-dim font-medium px-3 py-1.5 rounded-lg hover:bg-danger-muted transition-colors"
        >
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <div className="flex items-center space-x-2">
      <button
        onClick={() => connect({ connector: injected() })}
        className="bg-accent hover:bg-accent-dim text-surface-0 font-semibold text-sm px-4 py-2 rounded-lg transition-colors"
      >
        Connect Wallet
      </button>
      <button
        onClick={connectDemo}
        disabled={isDemoConnecting}
        className="bg-purple-600 hover:bg-purple-700 text-white font-semibold text-sm px-4 py-2 rounded-lg transition-colors disabled:opacity-50"
      >
        Try Demo
      </button>
    </div>
  );
};

export default ConnectWallet;
