import React, { createContext, useContext, ReactNode } from 'react';
import { analytics } from '../services/analytics';
import { usePerformanceMonitoring } from '../hooks/usePerformanceMonitoring';

interface AnalyticsContextValue {
  // Analytics tracking methods
  trackPositionOpen: (data: any) => void;
  trackTradeVolume: (data: any) => void;
  trackError: (error: Error, component?: string) => void;
  trackCustomEvent: (eventName: string, data: any) => void;

  // Performance monitoring
  startWalletConnection: (walletType: string) => void;
  endWalletConnection: (success: boolean, error?: string) => void;
  startTradeExecution: (marketId: string) => void;
  recordTradeStep: (step: 'preparation' | 'approval' | 'transaction' | 'confirmation') => void;
  endTradeExecution: (success: boolean, error?: string) => void;
  startPositionOpen: (marketId: string, leverage: number) => void;
  endPositionOpen: (success: boolean, error?: string, additionalData?: any) => void;
  trackPageLoad: (pageName: string) => () => void;
  trackCustomOperation: (operationName: string) => any;
}

const AnalyticsContext = createContext<AnalyticsContextValue | undefined>(undefined);

export const useAnalytics = () => {
  const context = useContext(AnalyticsContext);
  if (!context) {
    throw new Error('useAnalytics must be used within an AnalyticsProvider');
  }
  return context;
};

interface AnalyticsProviderProps {
  children: ReactNode;
}

export const AnalyticsProvider: React.FC<AnalyticsProviderProps> = ({ children }) => {
  const performanceMonitoring = usePerformanceMonitoring();

  const trackPositionOpen = (data: {
    marketId: string;
    direction: 'long' | 'short';
    leverage: number;
    collateral: string;
    estimatedNotional: string;
    success: boolean;
    errorMessage?: string;
    executionTime: number;
  }) => {
    analytics.trackPositionOpen(data);
  };

  const trackTradeVolume = (data: {
    marketId: string;
    volume: string;
    direction: 'long' | 'short';
    price: string;
    fees: string;
  }) => {
    analytics.trackTradeVolume(data);
  };

  const trackError = (error: Error, component?: string) => {
    analytics.trackError({
      errorType: 'javascript',
      errorMessage: error.message,
      errorStack: error.stack,
      component: component || 'Unknown',
      userAgent: navigator.userAgent,
      url: window.location.href
    });
  };

  const trackCustomEvent = (eventName: string, data: any) => {
    // For custom events that don't fit the standard categories
    console.log(`[Analytics] Custom event: ${eventName}`, data);

    // You could extend the analytics service to handle custom events
    analytics.trackPerformance({
      metric: 'TTFB', // Using TTFB as a generic custom metric
      value: Date.now(),
      rating: 'good'
    });
  };

  const value: AnalyticsContextValue = {
    // Analytics methods
    trackPositionOpen,
    trackTradeVolume,
    trackError,
    trackCustomEvent,

    // Performance monitoring methods (delegated to hook)
    startWalletConnection: performanceMonitoring.startWalletConnection,
    endWalletConnection: performanceMonitoring.endWalletConnection,
    startTradeExecution: performanceMonitoring.startTradeExecution,
    recordTradeStep: performanceMonitoring.recordTradeStep,
    endTradeExecution: performanceMonitoring.endTradeExecution,
    startPositionOpen: performanceMonitoring.startPositionOpen,
    endPositionOpen: performanceMonitoring.endPositionOpen,
    trackPageLoad: performanceMonitoring.trackPageLoad,
    trackCustomOperation: performanceMonitoring.trackCustomOperation,
  };

  return (
    <AnalyticsContext.Provider value={value}>
      {children}
    </AnalyticsContext.Provider>
  );
};

// Higher-order component for tracking component performance
export const withAnalytics = <P extends object>(
  WrappedComponent: React.ComponentType<P>,
  componentName: string
) => {
  return React.forwardRef<any, P>((props, ref) => {
    const { trackCustomEvent } = useAnalytics();

    React.useEffect(() => {
      const startTime = performance.now();
      trackCustomEvent('component_mount', {
        componentName,
        timestamp: Date.now()
      });

      return () => {
        const mountDuration = performance.now() - startTime;
        trackCustomEvent('component_unmount', {
          componentName,
          mountDuration,
          timestamp: Date.now()
        });
      };
    }, [trackCustomEvent]);

    return <WrappedComponent {...props} ref={ref} />;
  });
};