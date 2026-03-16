import React from 'react';
import { usePrivy } from '@privy-io/react-auth';

const ConnectWallet: React.FC = () => {
  const { ready, authenticated, user, login, logout } = usePrivy();

  // Don't render anything until Privy is ready
  if (!ready) {
    return (
      <div className="bg-accent hover:bg-accent-dim text-surface-0 font-semibold text-sm px-4 py-2 rounded-lg opacity-50">
        Loading...
      </div>
    );
  }

  if (authenticated && user) {
    // Show user's wallet address if available
    const address = user.wallet?.address;
    const shortAddr = address ? `${address.slice(0, 6)}...${address.slice(-4)}` : 'Connected';

    return (
      <div className="flex items-center space-x-2">
        <span className="text-sm font-mono text-gray-300 bg-surface-3 px-3 py-1.5 rounded-lg border border-border">
          {shortAddr}
        </span>
        <button
          onClick={logout}
          className="text-sm text-danger hover:text-danger-dim font-medium px-3 py-1.5 rounded-lg hover:bg-danger-muted transition-colors"
        >
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <button
      onClick={login}
      className="bg-accent hover:bg-accent-dim text-surface-0 font-semibold text-sm px-4 py-2 rounded-lg transition-colors"
    >
      Connect Wallet
    </button>
  );
};

export default ConnectWallet;
