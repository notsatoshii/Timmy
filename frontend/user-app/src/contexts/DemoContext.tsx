import React, { createContext, useContext, ReactNode } from 'react';

interface DemoContextType {
  isDemoMode: boolean;
  demoAddress: `0x${string}` | null;
  testWalletKey: string;
}

const DemoContext = createContext<DemoContextType | undefined>(undefined);

const TEST_WALLET_KEY = 'bf4b6a6e7c99d538edf38d0ac535a44729bb8c9907de5bb9494d852eb4e812ec';
const DEMO_ADDRESS = '0x742d35Cc6634C0532925a3b8D0a2dfABb3b9c8A0' as `0x${string}`; // Test wallet address

export const DemoProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const isDemoMode = localStorage.getItem('demo-mode') === 'true';
  const demoAddress = isDemoMode ? DEMO_ADDRESS : null;

  return (
    <DemoContext.Provider
      value={{
        isDemoMode,
        demoAddress,
        testWalletKey: TEST_WALLET_KEY,
      }}
    >
      {children}
    </DemoContext.Provider>
  );
};

export const useDemo = (): DemoContextType => {
  const context = useContext(DemoContext);
  if (context === undefined) {
    throw new Error('useDemo must be used within a DemoProvider');
  }
  return context;
};

export default DemoContext;