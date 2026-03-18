import { analytics } from './analytics';
import { errorMonitoring } from './errorMonitoring';

export interface HealthStatus {
  status: 'healthy' | 'warning' | 'critical' | 'down';
  timestamp: number;
  version: string;
  uptime: number;
  checks: {
    frontend: HealthCheck;
    wallet: HealthCheck;
    contracts: HealthCheck;
    network: HealthCheck;
    analytics: HealthCheck;
    errors: HealthCheck;
  };
  summary: {
    totalChecks: number;
    passing: number;
    warnings: number;
    failures: number;
  };
}

export interface HealthCheck {
  status: 'passing' | 'warning' | 'failing';
  message: string;
  timestamp: number;
  responseTime?: number;
  details?: Record<string, any>;
}

class HealthCheckService {
  private startTime: number;
  private isInitialized = false;

  constructor() {
    this.startTime = Date.now();
    this.initHealthEndpoint();
  }

  private initHealthEndpoint() {
    // Add health check endpoint to window for external monitoring
    if (typeof window !== 'undefined') {
      (window as any).__LEVER_HEALTH_CHECK__ = () => this.getFullHealthStatus();
      (window as any).__LEVER_HEALTH_SIMPLE__ = () => this.getSimpleHealthStatus();
    }
  }

  async getFullHealthStatus(): Promise<HealthStatus> {
    const startTime = performance.now();

    const checks = await Promise.all([
      this.checkFrontend(),
      this.checkWallet(),
      this.checkContracts(),
      this.checkNetwork(),
      this.checkAnalytics(),
      this.checkErrors()
    ]);

    const [frontend, wallet, contracts, network, analyticsCheck, errors] = checks;

    const summary = this.calculateSummary([frontend, wallet, contracts, network, analyticsCheck, errors]);
    const overallStatus = this.calculateOverallStatus(summary);

    return {
      status: overallStatus,
      timestamp: Date.now(),
      version: this.getVersion(),
      uptime: Date.now() - this.startTime,
      checks: {
        frontend,
        wallet,
        contracts,
        network,
        analytics: analyticsCheck,
        errors
      },
      summary
    };
  }

  async getSimpleHealthStatus(): Promise<{ status: string; uptime: number; timestamp: number }> {
    const fullStatus = await this.getFullHealthStatus();
    return {
      status: fullStatus.status,
      uptime: fullStatus.uptime,
      timestamp: fullStatus.timestamp
    };
  }

  private async checkFrontend(): Promise<HealthCheck> {
    const startTime = performance.now();

    try {
      // Check if React is mounted
      const reactRoot = document.getElementById('root');
      if (!reactRoot || !reactRoot.children.length) {
        return {
          status: 'failing',
          message: 'React application not mounted',
          timestamp: Date.now(),
          responseTime: performance.now() - startTime
        };
      }

      // Check for console errors
      const hasConsoleErrors = this.hasRecentConsoleErrors();

      // Check memory usage if available
      const memoryInfo = (performance as any).memory;
      const memoryUsage = memoryInfo ? memoryInfo.usedJSHeapSize / memoryInfo.totalJSHeapSize : 0;

      const responseTime = performance.now() - startTime;

      if (hasConsoleErrors || memoryUsage > 0.8) {
        return {
          status: 'warning',
          message: hasConsoleErrors ? 'Console errors detected' : 'High memory usage',
          timestamp: Date.now(),
          responseTime,
          details: { memoryUsage: memoryUsage * 100 }
        };
      }

      return {
        status: 'passing',
        message: 'Frontend application running normally',
        timestamp: Date.now(),
        responseTime,
        details: { memoryUsage: memoryUsage * 100 }
      };
    } catch (error) {
      return {
        status: 'failing',
        message: `Frontend check failed: ${error instanceof Error ? error.message : 'Unknown error'}`,
        timestamp: Date.now(),
        responseTime: performance.now() - startTime
      };
    }
  }

  private async checkWallet(): Promise<HealthCheck> {
    const startTime = performance.now();

    try {
      // Check if wallet providers are available
      const ethereum = (window as any).ethereum;
      const providers = [];

      if (ethereum) providers.push('MetaMask/Injected');
      if ((window as any).coinbaseWalletExtension) providers.push('Coinbase');

      const responseTime = performance.now() - startTime;

      if (providers.length === 0) {
        return {
          status: 'warning',
          message: 'No wallet providers detected',
          timestamp: Date.now(),
          responseTime,
          details: { availableProviders: providers }
        };
      }

      return {
        status: 'passing',
        message: `Wallet providers available: ${providers.join(', ')}`,
        timestamp: Date.now(),
        responseTime,
        details: { availableProviders: providers }
      };
    } catch (error) {
      return {
        status: 'failing',
        message: `Wallet check failed: ${error instanceof Error ? error.message : 'Unknown error'}`,
        timestamp: Date.now(),
        responseTime: performance.now() - startTime
      };
    }
  }

  private async checkContracts(): Promise<HealthCheck> {
    const startTime = performance.now();

    try {
      // This would normally check contract connectivity
      // For now, we'll check if contract config is loaded
      const contractConfig = await import('../config/contracts');
      const hasContracts = Object.keys(contractConfig).length > 0;

      const responseTime = performance.now() - startTime;

      if (!hasContracts) {
        return {
          status: 'failing',
          message: 'Contract configuration not loaded',
          timestamp: Date.now(),
          responseTime
        };
      }

      return {
        status: 'passing',
        message: 'Contract configuration loaded',
        timestamp: Date.now(),
        responseTime,
        details: { configLoaded: true }
      };
    } catch (error) {
      return {
        status: 'failing',
        message: `Contract check failed: ${error instanceof Error ? error.message : 'Unknown error'}`,
        timestamp: Date.now(),
        responseTime: performance.now() - startTime
      };
    }
  }

  private async checkNetwork(): Promise<HealthCheck> {
    const startTime = performance.now();

    try {
      // Check network connectivity
      const connected = navigator.onLine;

      // Try a simple network request to check actual connectivity
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 5000);

      try {
        await fetch('/manifest.json', {
          signal: controller.signal,
          cache: 'no-cache'
        });
        clearTimeout(timeoutId);
      } catch (fetchError) {
        clearTimeout(timeoutId);
        if ((fetchError as any).name === 'AbortError') {
          return {
            status: 'warning',
            message: 'Network request timeout',
            timestamp: Date.now(),
            responseTime: performance.now() - startTime
          };
        }
        throw fetchError;
      }

      const responseTime = performance.now() - startTime;

      if (!connected) {
        return {
          status: 'failing',
          message: 'No network connectivity',
          timestamp: Date.now(),
          responseTime
        };
      }

      return {
        status: 'passing',
        message: 'Network connectivity normal',
        timestamp: Date.now(),
        responseTime,
        details: { online: connected }
      };
    } catch (error) {
      return {
        status: 'failing',
        message: `Network check failed: ${error instanceof Error ? error.message : 'Unknown error'}`,
        timestamp: Date.now(),
        responseTime: performance.now() - startTime
      };
    }
  }

  private async checkAnalytics(): Promise<HealthCheck> {
    const startTime = performance.now();

    try {
      const analyticsStatus = analytics.getAnalyticsSummary();
      const responseTime = performance.now() - startTime;

      // Check if analytics is collecting data
      if (analyticsStatus.totalEvents === 0 && Date.now() - this.startTime > 60000) {
        return {
          status: 'warning',
          message: 'Analytics not collecting data after 1 minute',
          timestamp: Date.now(),
          responseTime,
          details: analyticsStatus
        };
      }

      // Check error rate
      if (analyticsStatus.errorRate > 0.1) {
        return {
          status: 'warning',
          message: `High error rate: ${(analyticsStatus.errorRate * 100).toFixed(1)}%`,
          timestamp: Date.now(),
          responseTime,
          details: analyticsStatus
        };
      }

      return {
        status: 'passing',
        message: 'Analytics functioning normally',
        timestamp: Date.now(),
        responseTime,
        details: analyticsStatus
      };
    } catch (error) {
      return {
        status: 'failing',
        message: `Analytics check failed: ${error instanceof Error ? error.message : 'Unknown error'}`,
        timestamp: Date.now(),
        responseTime: performance.now() - startTime
      };
    }
  }

  private async checkErrors(): Promise<HealthCheck> {
    const startTime = performance.now();

    try {
      const errorStatus = errorMonitoring.getErrorSummary();
      const responseTime = performance.now() - startTime;

      if (errorStatus.healthStatus === 'critical') {
        return {
          status: 'failing',
          message: 'Critical errors detected',
          timestamp: Date.now(),
          responseTime,
          details: errorStatus
        };
      }

      if (errorStatus.healthStatus === 'warning') {
        return {
          status: 'warning',
          message: 'Warning level errors detected',
          timestamp: Date.now(),
          responseTime,
          details: errorStatus
        };
      }

      return {
        status: 'passing',
        message: 'Error levels normal',
        timestamp: Date.now(),
        responseTime,
        details: errorStatus
      };
    } catch (error) {
      return {
        status: 'failing',
        message: `Error monitoring check failed: ${error instanceof Error ? error.message : 'Unknown error'}`,
        timestamp: Date.now(),
        responseTime: performance.now() - startTime
      };
    }
  }

  private calculateSummary(checks: HealthCheck[]) {
    const totalChecks = checks.length;
    const passing = checks.filter(c => c.status === 'passing').length;
    const warnings = checks.filter(c => c.status === 'warning').length;
    const failures = checks.filter(c => c.status === 'failing').length;

    return { totalChecks, passing, warnings, failures };
  }

  private calculateOverallStatus(summary: { passing: number; warnings: number; failures: number }): HealthStatus['status'] {
    if (summary.failures > 0) return 'critical';
    if (summary.warnings > 1) return 'warning';
    if (summary.warnings > 0) return 'warning';
    return 'healthy';
  }

  private getVersion(): string {
    return process.env.REACT_APP_VERSION || '0.1.0';
  }

  private hasRecentConsoleErrors(): boolean {
    // This is a simplified check - in production you might want to
    // track console errors more systematically
    return false;
  }

  // Expose health check endpoint for external monitoring
  createHealthCheckEndpoint() {
    // This could be extended to work with Express/Node.js backend
    // For client-side, we expose via window object
    return {
      path: '/__health',
      handler: () => this.getFullHealthStatus()
    };
  }
}

export const healthCheck = new HealthCheckService();
export default healthCheck;