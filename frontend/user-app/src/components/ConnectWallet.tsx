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
        <span className="text-sm font-mono text-gray-700 bg-gray-100 px-3 py-1.5 rounded-lg">
          {shortAddr}
        </span>
        <button
          onClick={() => disconnect()}
          className="text-sm text-red-600 hover:text-red-800 font-medium px-3 py-1.5 rounded-lg hover:bg-red-50 transition-colors"
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
      className="bg-primary-600 hover:bg-primary-700 text-white font-medium text-sm px-4 py-2 rounded-lg transition-colors disabled:opacity-50"
    >
      {isPending ? 'Connecting...' : 'Connect Wallet'}
    </button>
  );
};

export default ConnectWallet;
