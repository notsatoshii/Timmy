import React, { useState } from 'react';
import { useAccount, useConnect, useDisconnect } from 'wagmi';

const CONNECTOR_LABELS: Record<string, string> = {
  injected: 'Browser Wallet',
  metaMaskSDK: 'MetaMask',
  coinbaseWalletSDK: 'Coinbase Wallet',
};

const ConnectWallet: React.FC = () => {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const [showPicker, setShowPicker] = useState(false);

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
    <div className="relative">
      <button
        onClick={() => setShowPicker(!showPicker)}
        disabled={isPending}
        className="bg-accent hover:bg-accent-dim text-surface-0 font-semibold text-sm px-4 py-2 rounded-lg transition-colors disabled:opacity-50"
      >
        {isPending ? 'Connecting...' : 'Connect Wallet'}
      </button>

      {showPicker && (
        <div className="absolute right-0 top-full mt-2 w-56 bg-surface-2 border border-border rounded-lg shadow-card z-50 overflow-hidden">
          {connectors.map((connector) => (
            <button
              key={connector.uid}
              onClick={() => {
                connect({ connector });
                setShowPicker(false);
              }}
              className="w-full text-left px-4 py-3 text-sm text-gray-200 hover:bg-surface-3 transition-colors border-b border-border last:border-b-0"
            >
              {CONNECTOR_LABELS[connector.id] || connector.name}
            </button>
          ))}
        </div>
      )}
    </div>
  );
};

export default ConnectWallet;
