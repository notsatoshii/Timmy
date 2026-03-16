import React, { useState } from 'react';
import { useAccount, useConnect, useDisconnect } from 'wagmi';
import { injected } from 'wagmi/connectors';
import { setDemoMode } from '../connectors/demo';
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

      // Enable demo mode
      setDemoMode(true);

      // Force re-render by reloading the page
      window.location.reload();

    } catch (error) {
      console.error('Demo connection failed:', error);
      setDemoMode(false);
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
            setDemoMode(false);
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
