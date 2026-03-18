import React, { useState, useEffect } from 'react';
import { analytics } from '../services/analytics';
import { errorMonitoring } from '../services/errorMonitoring';
import { healthCheck } from '../services/healthCheck';

interface MonitoringDashboardProps {
  isVisible?: boolean;
  onClose?: () => void;
}

const MonitoringDashboard: React.FC<MonitoringDashboardProps> = ({
  isVisible = false,
  onClose
}) => {
  const [activeTab, setActiveTab] = useState<'analytics' | 'errors' | 'health'>('analytics');
  const [analyticsData, setAnalyticsData] = useState<any>(null);
  const [errorData, setErrorData] = useState<any>(null);
  const [healthData, setHealthData] = useState<any>(null);
  const [refreshInterval, setRefreshInterval] = useState<NodeJS.Timeout | null>(null);

  useEffect(() => {
    if (isVisible) {
      refreshData();
      const interval = setInterval(refreshData, 5000); // Refresh every 5 seconds
      setRefreshInterval(interval);

      return () => {
        if (interval) clearInterval(interval);
      };
    }
  }, [isVisible]);

  const refreshData = async () => {
    try {
      setAnalyticsData(analytics.getAnalyticsSummary());
      setErrorData(errorMonitoring.getErrorSummary());
      setHealthData(await healthCheck.getFullHealthStatus());
    } catch (error) {
      console.error('Failed to refresh monitoring data:', error);
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'healthy':
      case 'passing':
        return 'text-green-400';
      case 'warning':
        return 'text-yellow-400';
      case 'critical':
      case 'failing':
        return 'text-red-400';
      default:
        return 'text-gray-400';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy':
      case 'passing':
        return '✅';
      case 'warning':
        return '⚠️';
      case 'critical':
      case 'failing':
        return '❌';
      default:
        return '❓';
    }
  };

  if (!isVisible) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4">
      <div className="bg-surface-1 border border-border rounded-lg max-w-4xl w-full max-h-[80vh] overflow-hidden flex flex-col">
        {/* Header */}
        <div className="p-4 border-b border-border flex justify-between items-center">
          <h2 className="text-xl font-semibold text-gray-100">Production Monitoring</h2>
          {onClose && (
            <button
              onClick={onClose}
              className="text-gray-400 hover:text-gray-100 transition-colors"
            >
              ✕
            </button>
          )}
        </div>

        {/* Tabs */}
        <div className="flex border-b border-border">
          {['analytics', 'errors', 'health'].map((tab) => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab as any)}
              className={`px-4 py-2 capitalize font-medium transition-colors ${
                activeTab === tab
                  ? 'text-accent border-b-2 border-accent'
                  : 'text-gray-400 hover:text-gray-100'
              }`}
            >
              {tab}
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-4">
          {/* Analytics Tab */}
          {activeTab === 'analytics' && analyticsData && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div className="bg-surface-0 p-3 rounded border border-border">
                  <div className="text-sm text-gray-400">Total Events</div>
                  <div className="text-xl font-semibold text-gray-100">{analyticsData.totalEvents}</div>
                </div>
                <div className="bg-surface-0 p-3 rounded border border-border">
                  <div className="text-sm text-gray-400">Recent Events</div>
                  <div className="text-xl font-semibold text-gray-100">{analyticsData.recentEvents}</div>
                </div>
                <div className="bg-surface-0 p-3 rounded border border-border">
                  <div className="text-sm text-gray-400">Error Rate</div>
                  <div className={`text-xl font-semibold ${
                    analyticsData.errorRate > 0.1 ? 'text-red-400' : 'text-green-400'
                  }`}>
                    {(analyticsData.errorRate * 100).toFixed(1)}%
                  </div>
                </div>
                <div className="bg-surface-0 p-3 rounded border border-border">
                  <div className="text-sm text-gray-400">Avg Trade Time</div>
                  <div className="text-xl font-semibold text-gray-100">
                    {analyticsData.averageTradeTime.toFixed(0)}ms
                  </div>
                </div>
              </div>

              <div className="bg-surface-0 p-4 rounded border border-border">
                <h3 className="text-lg font-medium text-gray-100 mb-3">Position Metrics</h3>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <div className="text-sm text-gray-400">Successful Positions</div>
                    <div className="text-lg font-semibold text-green-400">
                      {analyticsData.successfulPositions}
                    </div>
                  </div>
                  <div>
                    <div className="text-sm text-gray-400">Failed Positions</div>
                    <div className="text-lg font-semibold text-red-400">
                      {analyticsData.failedPositions}
                    </div>
                  </div>
                </div>
              </div>

              <div className="bg-surface-0 p-4 rounded border border-border">
                <h3 className="text-lg font-medium text-gray-100 mb-3">Trade Metrics</h3>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <div className="text-sm text-gray-400">Successful Trades</div>
                    <div className="text-lg font-semibold text-green-400">
                      {analyticsData.successfulTrades}
                    </div>
                  </div>
                  <div>
                    <div className="text-sm text-gray-400">Failed Trades</div>
                    <div className="text-lg font-semibold text-red-400">
                      {analyticsData.failedTrades}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Errors Tab */}
          {activeTab === 'errors' && errorData && (
            <div className="space-y-4">
              <div className="bg-surface-0 p-4 rounded border border-border">
                <h3 className="text-lg font-medium text-gray-100 mb-3">Error Summary</h3>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div>
                    <div className="text-sm text-gray-400">Last 24h</div>
                    <div className="text-xl font-semibold text-gray-100">{errorData.last24h}</div>
                  </div>
                  <div>
                    <div className="text-sm text-gray-400">Last Hour</div>
                    <div className="text-xl font-semibold text-gray-100">{errorData.lastHour}</div>
                  </div>
                  <div>
                    <div className="text-sm text-gray-400">Total Alerts</div>
                    <div className="text-xl font-semibold text-gray-100">{errorData.totalAlerts}</div>
                  </div>
                  <div>
                    <div className="text-sm text-gray-400">Health Status</div>
                    <div className={`text-xl font-semibold ${getStatusColor(errorData.healthStatus)}`}>
                      {errorData.healthStatus}
                    </div>
                  </div>
                </div>
              </div>

              <div className="bg-surface-0 p-4 rounded border border-border">
                <h3 className="text-lg font-medium text-gray-100 mb-3">By Severity</h3>
                <div className="grid grid-cols-4 gap-4">
                  <div>
                    <div className="text-sm text-red-400">Critical</div>
                    <div className="text-lg font-semibold text-gray-100">{errorData.bySeverity.critical}</div>
                  </div>
                  <div>
                    <div className="text-sm text-orange-400">High</div>
                    <div className="text-lg font-semibold text-gray-100">{errorData.bySeverity.high}</div>
                  </div>
                  <div>
                    <div className="text-sm text-yellow-400">Medium</div>
                    <div className="text-lg font-semibold text-gray-100">{errorData.bySeverity.medium}</div>
                  </div>
                  <div>
                    <div className="text-sm text-blue-400">Low</div>
                    <div className="text-lg font-semibold text-gray-100">{errorData.bySeverity.low}</div>
                  </div>
                </div>
              </div>

              <div className="bg-surface-0 p-4 rounded border border-border">
                <h3 className="text-lg font-medium text-gray-100 mb-3">Recent Alerts</h3>
                <div className="space-y-2 max-h-64 overflow-y-auto">
                  {errorMonitoring.getAllAlerts().slice(-10).reverse().map((alert) => (
                    <div key={alert.id} className="text-sm border-b border-border pb-2">
                      <div className="flex justify-between items-start">
                        <span className={`font-medium ${getStatusColor(alert.severity)}`}>
                          {alert.severity.toUpperCase()}
                        </span>
                        <span className="text-gray-500 text-xs">
                          {new Date(alert.timestamp).toLocaleTimeString()}
                        </span>
                      </div>
                      <div className="text-gray-300 mt-1">{alert.message}</div>
                      {alert.component && (
                        <div className="text-gray-500 text-xs">{alert.component}</div>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* Health Tab */}
          {activeTab === 'health' && healthData && (
            <div className="space-y-4">
              <div className="bg-surface-0 p-4 rounded border border-border">
                <div className="flex justify-between items-center mb-4">
                  <h3 className="text-lg font-medium text-gray-100">Overall Health</h3>
                  <div className={`text-xl font-semibold ${getStatusColor(healthData.status)}`}>
                    {getStatusIcon(healthData.status)} {healthData.status.toUpperCase()}
                  </div>
                </div>
                <div className="grid grid-cols-3 gap-4">
                  <div>
                    <div className="text-sm text-gray-400">Uptime</div>
                    <div className="text-lg font-semibold text-gray-100">
                      {Math.floor(healthData.uptime / 60000)}m
                    </div>
                  </div>
                  <div>
                    <div className="text-sm text-gray-400">Version</div>
                    <div className="text-lg font-semibold text-gray-100">{healthData.version}</div>
                  </div>
                  <div>
                    <div className="text-sm text-gray-400">Checks</div>
                    <div className="text-lg font-semibold text-gray-100">
                      {healthData.summary.passing}/{healthData.summary.totalChecks}
                    </div>
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {Object.entries(healthData.checks).map(([checkName, check]: [string, any]) => (
                  <div key={checkName} className="bg-surface-0 p-4 rounded border border-border">
                    <div className="flex justify-between items-center mb-2">
                      <h4 className="font-medium text-gray-100 capitalize">{checkName}</h4>
                      <span className={`text-sm ${getStatusColor(check.status)}`}>
                        {getStatusIcon(check.status)} {check.status}
                      </span>
                    </div>
                    <div className="text-sm text-gray-400 mb-2">{check.message}</div>
                    {check.responseTime && (
                      <div className="text-xs text-gray-500">
                        Response: {check.responseTime.toFixed(0)}ms
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="p-4 border-t border-border text-sm text-gray-500">
          <div className="flex justify-between items-center">
            <span>Auto-refresh every 5 seconds</span>
            <button
              onClick={refreshData}
              className="text-accent hover:text-accent-dim transition-colors"
            >
              Refresh Now
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default MonitoringDashboard;