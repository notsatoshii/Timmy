import { getCLS, getFID, getFCP, getLCP, getTTFB } from 'web-vitals';

// Types for analytics events
export interface AnalyticsEvent {
  eventType: 'position_open' | 'trade_volume' | 'error' | 'wallet_connection' | 'trade_execution' | 'performance';
  timestamp: number;
  userId?: string;
  sessionId: string;
  data: Record<string, any>;
}

export interface PositionOpenEvent {
  marketId: string;
  direction: 'long' | 'short';
  leverage: number;
  collateral: string;
  estimatedNotional: string;
  success: boolean;
  errorMessage?: string;
  executionTime: number;
}

export interface TradeVolumeEvent {
  marketId: string;
  volume: string;
  direction: 'long' | 'short';
  price: string;
  fees: string;
}

export interface ErrorEvent {
  errorType: 'javascript' | 'transaction' | 'wallet' | 'network';
  errorMessage: string;
  errorStack?: string;
  component?: string;
  userAgent: string;
  url: string;
}

export interface WalletConnectionEvent {
  walletType: string;
  success: boolean;
  connectionTime: number;
  errorMessage?: string;
}

export interface TradeExecutionEvent {
  marketId: string;
  executionTime: number;
  gasUsed?: string;
  success: boolean;
  errorMessage?: string;
  steps: {
    approval?: number;
    transaction?: number;
    confirmation?: number;
  };
}

export interface PerformanceEvent {
  metric: 'CLS' | 'FID' | 'FCP' | 'LCP' | 'TTFB';
  value: number;
  rating: 'good' | 'needs-improvement' | 'poor';
}

class AnalyticsService {
  private sessionId: string;
  private events: AnalyticsEvent[] = [];
  private isProduction: boolean;
  private maxStoredEvents = 100;

  constructor() {
    this.sessionId = this.generateSessionId();
    this.isProduction = process.env.NODE_ENV === 'production';
    this.initPerformanceMonitoring();
  }

  private generateSessionId(): string {
    return `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  private initPerformanceMonitoring() {
    if (!this.isProduction) return;

    // Monitor Web Vitals
    getCLS(this.onVitalsMetric.bind(this));
    getFID(this.onVitalsMetric.bind(this));
    getFCP(this.onVitalsMetric.bind(this));
    getLCP(this.onVitalsMetric.bind(this));
    getTTFB(this.onVitalsMetric.bind(this));
  }

  private onVitalsMetric(metric: any) {
    this.trackPerformance({
      metric: metric.name,
      value: metric.value,
      rating: metric.rating
    });
  }

  private async sendEvent(event: AnalyticsEvent) {
    if (this.isProduction) {
      try {
        // In production, you would send to your analytics service
        // For now, we'll log and store locally
        console.log('[Analytics]', event);

        // Could integrate with services like:
        // - Google Analytics 4
        // - Mixpanel
        // - PostHog
        // - Custom analytics endpoint

        // Example: await fetch('/api/analytics', { method: 'POST', body: JSON.stringify(event) });
      } catch (error) {
        console.error('Failed to send analytics event:', error);
      }
    }

    // Store locally for debugging
    this.events.push(event);
    if (this.events.length > this.maxStoredEvents) {
      this.events = this.events.slice(-this.maxStoredEvents);
    }
  }

  trackPositionOpen(data: PositionOpenEvent) {
    this.sendEvent({
      eventType: 'position_open',
      timestamp: Date.now(),
      sessionId: this.sessionId,
      data
    });
  }

  trackTradeVolume(data: TradeVolumeEvent) {
    this.sendEvent({
      eventType: 'trade_volume',
      timestamp: Date.now(),
      sessionId: this.sessionId,
      data
    });
  }

  trackError(data: ErrorEvent) {
    this.sendEvent({
      eventType: 'error',
      timestamp: Date.now(),
      sessionId: this.sessionId,
      data
    });
  }

  trackWalletConnection(data: WalletConnectionEvent) {
    this.sendEvent({
      eventType: 'wallet_connection',
      timestamp: Date.now(),
      sessionId: this.sessionId,
      data
    });
  }

  trackTradeExecution(data: TradeExecutionEvent) {
    this.sendEvent({
      eventType: 'trade_execution',
      timestamp: Date.now(),
      sessionId: this.sessionId,
      data
    });
  }

  trackPerformance(data: PerformanceEvent) {
    this.sendEvent({
      eventType: 'performance',
      timestamp: Date.now(),
      sessionId: this.sessionId,
      data
    });
  }

  // Custom page timing
  trackPageLoad(pageName: string, loadTime: number) {
    this.trackPerformance({
      metric: 'TTFB',
      value: loadTime,
      rating: loadTime < 800 ? 'good' : loadTime < 1800 ? 'needs-improvement' : 'poor'
    });
  }

  // Get analytics summary for health checks
  getAnalyticsSummary() {
    const now = Date.now();
    const last24h = now - 24 * 60 * 60 * 1000;
    const recentEvents = this.events.filter(e => e.timestamp > last24h);

    const errorEvents = recentEvents.filter(e => e.eventType === 'error');
    const positionEvents = recentEvents.filter(e => e.eventType === 'position_open');
    const tradeEvents = recentEvents.filter(e => e.eventType === 'trade_execution');

    return {
      sessionId: this.sessionId,
      totalEvents: this.events.length,
      recentEvents: recentEvents.length,
      errorRate: recentEvents.length > 0 ? errorEvents.length / recentEvents.length : 0,
      successfulPositions: positionEvents.filter(e => e.data.success).length,
      failedPositions: positionEvents.filter(e => !e.data.success).length,
      successfulTrades: tradeEvents.filter(e => e.data.success).length,
      failedTrades: tradeEvents.filter(e => !e.data.success).length,
      averageTradeTime: this.calculateAverageTradeTime(tradeEvents)
    };
  }

  private calculateAverageTradeTime(tradeEvents: AnalyticsEvent[]): number {
    if (tradeEvents.length === 0) return 0;
    const totalTime = tradeEvents.reduce((sum, event) => sum + (event.data.executionTime || 0), 0);
    return totalTime / tradeEvents.length;
  }

  // Debug method to get all events
  getAllEvents(): AnalyticsEvent[] {
    return [...this.events];
  }

  // Clear events (for testing)
  clearEvents() {
    this.events = [];
  }
}

// Global analytics instance
export const analytics = new AnalyticsService();

// Performance timing utility
export class PerformanceTracker {
  private startTime: number = 0;
  private name: string;

  constructor(name: string) {
    this.name = name;
  }

  start() {
    this.startTime = performance.now();
    return this;
  }

  end() {
    if (this.startTime === 0) {
      console.warn('PerformanceTracker: start() was not called');
      return 0;
    }

    const duration = performance.now() - this.startTime;
    console.log(`[Performance] ${this.name}: ${duration.toFixed(2)}ms`);

    // Track significant operations
    if (this.name.includes('wallet') || this.name.includes('trade') || this.name.includes('position')) {
      analytics.trackPerformance({
        metric: 'TTFB', // Using TTFB as custom timing metric
        value: duration,
        rating: duration < 1000 ? 'good' : duration < 3000 ? 'needs-improvement' : 'poor'
      });
    }

    return duration;
  }
}

export default analytics;