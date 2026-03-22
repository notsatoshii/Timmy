import { analytics } from './analytics';

export interface ErrorAlert {
  id: string;
  timestamp: number;
  severity: 'low' | 'medium' | 'high' | 'critical';
  message: string;
  component?: string;
  stack?: string;
  userAgent: string;
  url: string;
  userId?: string;
  sessionId: string;
}

class ErrorMonitoringService {
  private alerts: ErrorAlert[] = [];
  private maxAlerts = 50;
  private criticalErrorThreshold = 5; // Critical if 5+ errors in 1 minute
  private isProduction = process.env.NODE_ENV === 'production';

  constructor() {
    this.initGlobalErrorHandler();
    this.initUnhandledRejectionHandler();
  }

  private initGlobalErrorHandler() {
    window.addEventListener('error', (event) => {
      this.captureError({
        errorType: 'javascript',
        errorMessage: event.message,
        errorStack: event.error?.stack,
        component: 'GlobalHandler',
        userAgent: navigator.userAgent,
        url: window.location.href
      }, 'high');
    });
  }

  private initUnhandledRejectionHandler() {
    window.addEventListener('unhandledrejection', (event) => {
      this.captureError({
        errorType: 'javascript',
        errorMessage: `Unhandled Promise Rejection: ${event.reason}`,
        errorStack: event.reason?.stack,
        component: 'PromiseHandler',
        userAgent: navigator.userAgent,
        url: window.location.href
      }, 'medium');
    });
  }

  captureError(errorData: any, severity: 'low' | 'medium' | 'high' | 'critical' = 'medium') {
    const alert: ErrorAlert = {
      id: `error_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      timestamp: Date.now(),
      severity,
      message: errorData.errorMessage || 'Unknown error',
      component: errorData.component,
      stack: errorData.errorStack,
      userAgent: navigator.userAgent,
      url: window.location.href,
      sessionId: analytics['sessionId'] // Access private property
    };

    this.alerts.push(alert);
    if (this.alerts.length > this.maxAlerts) {
      this.alerts = this.alerts.slice(-this.maxAlerts);
    }

    // Track in analytics
    analytics.trackError({
      errorType: errorData.errorType || 'javascript',
      errorMessage: alert.message,
      errorStack: alert.stack,
      component: alert.component,
      userAgent: alert.userAgent,
      url: alert.url
    });

    // Send alert to monitoring service in production
    if (this.isProduction) {
      this.sendAlert(alert);
    }

    // Check if we need to escalate
    this.checkCriticalThreshold();

    console.error('[ErrorMonitoring]', alert);
  }

  private async sendAlert(alert: ErrorAlert) {
    try {
      // In production, integrate with error monitoring services:
      // - Sentry
      // - Bugsnag
      // - LogRocket
      // - Custom error reporting endpoint

      // Example implementation:
      // await fetch('/api/errors', {
      //   method: 'POST',
      //   headers: { 'Content-Type': 'application/json' },
      //   body: JSON.stringify(alert)
      // });

      console.log('[ErrorMonitoring] Alert sent:', alert.id);
    } catch (error) {
      console.error('[ErrorMonitoring] Failed to send alert:', error);
    }
  }

  private checkCriticalThreshold() {
    const oneMinuteAgo = Date.now() - 60 * 1000;
    const recentErrors = this.alerts.filter(alert => alert.timestamp > oneMinuteAgo);

    if (recentErrors.length >= this.criticalErrorThreshold) {
      this.escalateToCritical(recentErrors);
    }
  }

  private escalateToCritical(recentErrors: ErrorAlert[]) {
    const criticalAlert: ErrorAlert = {
      id: `critical_${Date.now()}`,
      timestamp: Date.now(),
      severity: 'critical',
      message: `Critical: ${recentErrors.length} errors in the last minute`,
      component: 'ErrorMonitoring',
      userAgent: navigator.userAgent,
      url: window.location.href,
      sessionId: analytics['sessionId']
    };

    this.alerts.push(criticalAlert);

    // In production, this could trigger immediate notifications
    if (this.isProduction) {
      this.sendAlert(criticalAlert);
      this.sendImmediateAlert(criticalAlert, recentErrors);
    }

    console.error('[ErrorMonitoring] CRITICAL THRESHOLD EXCEEDED', criticalAlert);
  }

  private async sendImmediateAlert(criticalAlert: ErrorAlert, recentErrors: ErrorAlert[]) {
    // This could integrate with:
    // - PagerDuty for immediate alerts
    // - Slack webhooks
    // - Email notifications
    // - SMS alerts for critical issues

    console.log('[ErrorMonitoring] Immediate alert triggered', {
      critical: criticalAlert,
      recentErrors: recentErrors.length
    });
  }

  // React Error Boundary integration
  captureReactError(error: Error, errorInfo: React.ErrorInfo, component: string) {
    this.captureError({
      errorType: 'javascript',
      errorMessage: error.message,
      errorStack: error.stack,
      component,
      userAgent: navigator.userAgent,
      url: window.location.href,
      reactErrorInfo: errorInfo
    }, 'high');
  }

  // Transaction error tracking
  captureTransactionError(error: any, txData: any) {
    this.captureError({
      errorType: 'transaction',
      errorMessage: error.message || 'Transaction failed',
      errorStack: error.stack,
      component: 'TransactionHandler',
      userAgent: navigator.userAgent,
      url: window.location.href,
      transactionData: txData
    }, 'medium');
  }

  // Wallet error tracking
  captureWalletError(error: any, walletType: string) {
    this.captureError({
      errorType: 'wallet',
      errorMessage: error.message || 'Wallet connection failed',
      errorStack: error.stack,
      component: 'WalletHandler',
      userAgent: navigator.userAgent,
      url: window.location.href,
      walletType
    }, 'high');
  }

  // Network error tracking
  captureNetworkError(error: any, endpoint: string) {
    this.captureError({
      errorType: 'network',
      errorMessage: error.message || 'Network request failed',
      errorStack: error.stack,
      component: 'NetworkHandler',
      userAgent: navigator.userAgent,
      url: window.location.href,
      endpoint
    }, 'medium');
  }

  // Get error summary for health checks
  getErrorSummary() {
    const now = Date.now();
    const last24h = now - 24 * 60 * 60 * 1000;
    const lastHour = now - 60 * 60 * 1000;

    const recent24h = this.alerts.filter(alert => alert.timestamp > last24h);
    const recentHour = this.alerts.filter(alert => alert.timestamp > lastHour);

    const bySeverity = {
      critical: recent24h.filter(a => a.severity === 'critical').length,
      high: recent24h.filter(a => a.severity === 'high').length,
      medium: recent24h.filter(a => a.severity === 'medium').length,
      low: recent24h.filter(a => a.severity === 'low').length
    };

    return {
      totalAlerts: this.alerts.length,
      last24h: recent24h.length,
      lastHour: recentHour.length,
      bySeverity,
      healthStatus: this.getHealthStatus(bySeverity, recentHour.length)
    };
  }

  private getHealthStatus(bySeverity: any, lastHourErrors: number): 'healthy' | 'warning' | 'critical' {
    if (bySeverity.critical > 0 || lastHourErrors >= this.criticalErrorThreshold) {
      return 'critical';
    }
    if (bySeverity.high > 2 || lastHourErrors > 10) {
      return 'warning';
    }
    return 'healthy';
  }

  // Get all alerts (for debugging)
  getAllAlerts(): ErrorAlert[] {
    return [...this.alerts];
  }

  // Clear alerts (for testing)
  clearAlerts() {
    this.alerts = [];
  }
}

export const errorMonitoring = new ErrorMonitoringService();
export default errorMonitoring;