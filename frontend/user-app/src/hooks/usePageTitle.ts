import { useEffect } from 'react';

type PageSection = 'markets' | 'trading' | 'vault' | 'positions' | 'market-detail';

const PAGE_TITLES: Record<PageSection, string> = {
  markets: 'Markets - LEVER Protocol',
  trading: 'Trading - LEVER Protocol',
  vault: 'Liquidity Vault - LEVER Protocol',
  positions: 'My Positions - LEVER Protocol',
  'market-detail': 'Market Details - LEVER Protocol'
};

/**
 * Hook to manage dynamic page titles based on current section
 * @param section - Current page section
 * @param customSuffix - Optional custom suffix for specific scenarios
 */
export const usePageTitle = (section: PageSection, customSuffix?: string) => {
  useEffect(() => {
    const baseTitle = PAGE_TITLES[section] || 'LEVER Protocol - Synthetic Perpetuals';
    const title = customSuffix ? `${customSuffix} - LEVER Protocol` : baseTitle;

    document.title = title;

    // Cleanup function to reset to default title on unmount
    return () => {
      document.title = 'LEVER Protocol - Synthetic Perpetuals';
    };
  }, [section, customSuffix]);
};

/**
 * Utility function to update page title without using the hook
 * Useful for one-off title updates
 */
export const updatePageTitle = (section: PageSection, customSuffix?: string) => {
  const baseTitle = PAGE_TITLES[section] || 'LEVER Protocol - Synthetic Perpetuals';
  const title = customSuffix ? `${customSuffix} - LEVER Protocol` : baseTitle;
  document.title = title;
};