import { useCallback, useRef } from 'react';
import { analytics, PerformanceTracker } from '../services/analytics';
import { errorMonitoring } from '../services/errorMonitoring';

interface PerformanceMetrics {
  walletConnection: {
    startTime: number;
    endTime?: number;
    duration?: number;
    success?: boolean;
    walletType?: string;
    error?: string;
  };
  tradeExecution: {
    startTime: number;
    endTime?: number;
    duration?: number;
    success?: boolean;
    marketId?: string;
    steps: {
      preparation?: number;
      approval?: number;
      transaction?: number;
      confirmation?: number;
    };
    error?: string;
  };
  positionOpen: {
    startTime: number;
    endTime?: number;
    duration?: number;
    success?: boolean;
    marketId?: string;
    leverage?: number;
    error?: string;
  };
}

export const usePerformanceMonitoring = () => {
  const metrics = useRef<PerformanceMetrics>({
    walletConnection: { startTime: 0 },
    tradeExecution: { startTime: 0, steps: {} },
    positionOpen: { startTime: 0 }
  });

  const startWalletConnection = useCallback((walletType: string) => {
    console.log(`[Performance] Starting wallet connection: ${walletType}`);
    metrics.current.walletConnection = {
      startTime: performance.now(),
      walletType
    };
  }, []);

  const endWalletConnection = useCallback((success: boolean, error?: string) => {
    const metric = metrics.current.walletConnection;
    const endTime = performance.now();
    const duration = endTime - metric.startTime;

    metric.endTime = endTime;
    metric.duration = duration;
    metric.success = success;
    metric.error = error;

    console.log(`[Performance] Wallet connection ${success ? 'succeeded' : 'failed'}: ${duration.toFixed(2)}ms`);

    // Track in analytics
    analytics.trackWalletConnection({
      walletType: metric.walletType || 'unknown',
      success,
      connectionTime: duration,
      errorMessage: error
    });

    // Track performance metric
    analytics.trackPerformance({
      metric: 'TTFB',
      value: duration,
      rating: duration < 2000 ? 'good' : duration < 5000 ? 'needs-improvement' : 'poor'
    });

    if (!success && error) {
      errorMonitoring.captureWalletError(
        new Error(error),
        metric.walletType || 'unknown'
      );
    }

    return duration;
  }, []);

  const startTradeExecution = useCallback((marketId: string) => {
    console.log(`[Performance] Starting trade execution: ${marketId}`);
    metrics.current.tradeExecution = {
      startTime: performance.now(),
      marketId,
      steps: {}
    };
  }, []);

  const recordTradeStep = useCallback((step: 'preparation' | 'approval' | 'transaction' | 'confirmation') => {
    const metric = metrics.current.tradeExecution;
    const stepTime = performance.now() - metric.startTime;
    metric.steps[step] = stepTime;

    console.log(`[Performance] Trade step ${step}: ${stepTime.toFixed(2)}ms`);
  }, []);

  const endTradeExecution = useCallback((success: boolean, error?: string) => {
    const metric = metrics.current.tradeExecution;
    const endTime = performance.now();
    const duration = endTime - metric.startTime;

    metric.endTime = endTime;
    metric.duration = duration;
    metric.success = success;
    metric.error = error;

    console.log(`[Performance] Trade execution ${success ? 'succeeded' : 'failed'}: ${duration.toFixed(2)}ms`);
    console.log('[Performance] Trade steps:', metric.steps);

    // Track in analytics
    analytics.trackTradeExecution({
      marketId: metric.marketId || 'unknown',
      executionTime: duration,
      success,
      errorMessage: error,
      steps: metric.steps
    });

    // Track performance metric
    analytics.trackPerformance({
      metric: 'TTFB',
      value: duration,
      rating: duration < 5000 ? 'good' : duration < 10000 ? 'needs-improvement' : 'poor'
    });

    if (!success && error) {
      errorMonitoring.captureTransactionError(
        new Error(error),
        { marketId: metric.marketId, steps: metric.steps }
      );
    }

    return duration;
  }, []);

  const startPositionOpen = useCallback((marketId: string, leverage: number) => {
    console.log(`[Performance] Starting position open: ${marketId} (${leverage}x)`);
    metrics.current.positionOpen = {
      startTime: performance.now(),
      marketId,
      leverage
    };
  }, []);

  const endPositionOpen = useCallback((success: boolean, error?: string, additionalData?: any) => {
    const metric = metrics.current.positionOpen;
    const endTime = performance.now();
    const duration = endTime - metric.startTime;

    metric.endTime = endTime;
    metric.duration = duration;
    metric.success = success;
    metric.error = error;

    console.log(`[Performance] Position open ${success ? 'succeeded' : 'failed'}: ${duration.toFixed(2)}ms`);

    // Track in analytics
    analytics.trackPositionOpen({
      marketId: metric.marketId || 'unknown',
      direction: additionalData?.direction || 'unknown',
      leverage: metric.leverage || 1,
      collateral: additionalData?.collateral || '0',
      estimatedNotional: additionalData?.estimatedNotional || '0',
      success,
      errorMessage: error,
      executionTime: duration
    });

    // Track performance metric
    analytics.trackPerformance({
      metric: 'TTFB',
      value: duration,
      rating: duration < 3000 ? 'good' : duration < 8000 ? 'needs-improvement' : 'poor'
    });

    if (!success && error) {
      errorMonitoring.captureError({
        errorType: 'transaction',
        errorMessage: error,
        component: 'PositionOpen',
        userAgent: navigator.userAgent,
        url: window.location.href,
        positionData: { marketId: metric.marketId, leverage: metric.leverage }
      }, 'medium');
    }

    return duration;
  }, []);

  const trackPageLoad = useCallback((pageName: string) => {
    const tracker = new PerformanceTracker(`Page Load: ${pageName}`);
    tracker.start();

    // Return cleanup function
    return () => {
      const duration = tracker.end();
      analytics.trackPageLoad(pageName, duration);
    };
  }, []);

  const trackCustomOperation = useCallback((operationName: string) => {
    const tracker = new PerformanceTracker(operationName);
    tracker.start();

    return {
      end: () => tracker.end(),
      endWithSuccess: (success: boolean, error?: string) => {
        const duration = tracker.end();

        analytics.trackPerformance({
          metric: 'TTFB',
          value: duration,
          rating: duration < 1000 ? 'good' : duration < 3000 ? 'needs-improvement' : 'poor'
        });

        if (!success && error) {
          errorMonitoring.captureError({
            errorType: 'javascript',
            errorMessage: error,
            component: operationName,
            userAgent: navigator.userAgent,
            url: window.location.href
          }, 'medium');
        }

        return duration;
      }
    };
  }, []);

  const getCurrentMetrics = useCallback(() => {
    return { ...metrics.current };
  }, []);

  return {
    // Wallet connection tracking
    startWalletConnection,
    endWalletConnection,

    // Trade execution tracking
    startTradeExecution,
    recordTradeStep,
    endTradeExecution,

    // Position opening tracking
    startPositionOpen,
    endPositionOpen,

    // Page load tracking
    trackPageLoad,

    // Custom operation tracking
    trackCustomOperation,

    // Get current metrics
    getCurrentMetrics
  };
};

// Performance monitoring hook for React components
export const useComponentPerformance = (componentName: string) => {
  const renderStartTime = useRef(performance.now());
  const mountTime = useRef(0);

  const recordMount = useCallback(() => {
    mountTime.current = performance.now() - renderStartTime.current;
    console.log(`[Performance] ${componentName} mounted in ${mountTime.current.toFixed(2)}ms`);

    // Track slow component mounts
    if (mountTime.current > 1000) {
      analytics.trackPerformance({
        metric: 'TTFB',
        value: mountTime.current,
        rating: 'poor'
      });
    }
  }, [componentName]);

  const recordRender = useCallback(() => {
    const renderTime = performance.now() - renderStartTime.current;
    console.log(`[Performance] ${componentName} render time: ${renderTime.toFixed(2)}ms`);

    renderStartTime.current = performance.now();
  }, [componentName]);

  return {
    recordMount,
    recordRender,
    getMountTime: () => mountTime.current
  };
};

export default usePerformanceMonitoring;