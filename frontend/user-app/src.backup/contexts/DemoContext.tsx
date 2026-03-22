import React, { createContext, useContext, ReactNode } from 'react';
import { isDemoMode as checkDemoMode, DEMO_ADDRESS, TEST_WALLET_KEY } from '../connectors/demo';

interface DemoContextType {
  isDemoMode: boolean;
  demoAddress: `0x${string}` | null;
  testWalletKey: string;
}

const DemoContext = createContext<DemoContextType | undefined>(undefined);

export const DemoProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const isDemoMode = checkDemoMode();
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