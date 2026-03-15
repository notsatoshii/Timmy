import React from 'react';
import { useAccount, useConnect, useDisconnect } from 'wagmi';

const ConnectWallet: React.FC = () => {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();

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
    <button
      onClick={() => {
        const connector = connectors[0];
        if (connector) connect({ connector });
      }}
      disabled={isPending}
      className="bg-accent hover:bg-accent-dim text-surface-0 font-semibold text-sm px-4 py-2 rounded-lg transition-colors disabled:opacity-50"
    >
      {isPending ? 'Connecting...' : 'Connect Wallet'}
    </button>
  );
};

export default ConnectWallet;
