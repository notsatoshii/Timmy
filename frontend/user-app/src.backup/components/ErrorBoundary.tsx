import React, { Component, ErrorInfo, ReactNode } from 'react';
import { errorMonitoring } from '../services/errorMonitoring';

interface Props {
  children: ReactNode;
  panelName: string;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
  errorId: string | null;
}

class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null, errorInfo: null, errorId: null };
  }

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { hasError: true };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error(`Error caught in ${this.props.panelName} panel:`, error);
    console.error('Error details:', errorInfo);

    // Capture error in monitoring system
    errorMonitoring.captureReactError(error, errorInfo, this.props.panelName);

    const errorId = `${this.props.panelName}_${Date.now()}`;

    this.setState({
      error,
      errorInfo,
      errorId
    });
  }

  handleRetry = () => {
    console.log(`[ErrorBoundary] Retrying ${this.props.panelName} panel`);
    this.setState({ hasError: false, error: null, errorInfo: null, errorId: null });
  };

  handleReportError = () => {
    if (this.state.errorId) {
      console.log(`[ErrorBoundary] User reported error: ${this.state.errorId}`);
      // In production, this could open a support ticket or send feedback
    }
  };

  render() {
    if (this.state.hasError) {
      // Professional Error Display for Investors
      return (
        <div className="lever-card-professional border-danger/30">
          <div className="flex flex-col items-center space-y-6">
            {/* Professional Error Icon with Animation */}
            <div className="relative">
              <div className="w-20 h-20 bg-gradient-to-br from-danger/20 to-danger/5 rounded-full flex items-center justify-center backdrop-blur-sm border border-danger/20">
                <svg className="w-10 h-10 text-danger animate-pulse" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.732-.833-2.5 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
                </svg>
              </div>
              {/* Glow effect */}
              <div className="absolute inset-0 w-20 h-20 bg-danger/10 rounded-full animate-ping" />
            </div>

            {/* Professional Error Header */}
            <div className="text-center space-y-3">
              <div className="space-y-1">
                <h3 className="text-xl font-semibold text-ivory font-display">
                  Panel Error
                </h3>
                <div className="text-sm font-mono text-danger bg-danger/10 px-3 py-1 rounded-full border border-danger/20">
                  {this.props.panelName} Module
                </div>
              </div>

              <p className="text-steel max-w-lg leading-relaxed">
                The {this.props.panelName.toLowerCase()} component has encountered an unexpected error.
                Our monitoring systems have been automatically notified. This is likely a temporary issue
                that will resolve with a retry.
              </p>

              {this.state.errorId && (
                <div className="bg-surface-2 border border-border rounded-lg p-3">
                  <div className="text-xs text-steel/70 mb-1">Error Reference</div>
                  <div className="text-sm font-mono text-accent">{this.state.errorId}</div>
                  <div className="text-xs text-steel/60 mt-1">
                    {new Date().toLocaleString()} • Auto-reported to monitoring
                  </div>
                </div>
              )}
            </div>

            {/* Professional Error Details (Collapsible in Production) */}
            {process.env.NODE_ENV === 'development' && this.state.error && (
              <details className="w-full max-w-2xl">
                <summary className="cursor-pointer text-sm text-steel/70 hover:text-steel transition-colors mb-3 font-mono">
                  Developer Details (Development Only)
                </summary>
                <div className="bg-surface-0 border border-border rounded-lg p-4 text-left text-sm font-mono max-w-full overflow-auto">
                  <div className="font-semibold text-danger mb-2">Error Message:</div>
                  <div className="text-gray-300 whitespace-pre-wrap mb-4 bg-surface-2 p-2 rounded">
                    {this.state.error.toString()}
                  </div>
                  {this.state.errorInfo && (
                    <>
                      <div className="font-semibold text-warning mb-2">Component Stack:</div>
                      <div className="text-gray-400 whitespace-pre-wrap text-xs bg-surface-2 p-2 rounded">
                        {this.state.errorInfo.componentStack}
                      </div>
                    </>
                  )}
                </div>
              </details>
            )}

            {/* Professional Action Buttons */}
            <div className="flex flex-wrap gap-3 justify-center">
              <button
                onClick={this.handleRetry}
                className="lever-btn-primary"
              >
                <span>Retry Component</span>
              </button>

              <button
                onClick={() => window.location.reload()}
                className="lever-btn-secondary"
              >
                <span>Reload Application</span>
              </button>

              {this.state.errorId && (
                <button
                  onClick={this.handleReportError}
                  className="lever-btn-outline text-sm"
                >
                  <span>Contact Support</span>
                </button>
              )}
            </div>

            {/* Professional Status Footer */}
            <div className="w-full pt-4 border-t border-border/30">
              <div className="flex justify-center items-center space-x-6 text-xs">
                <div className="flex items-center space-x-1.5">
                  <div className="w-1.5 h-1.5 bg-long rounded-full animate-pulse" />
                  <span className="text-steel/70">System Status: Operational</span>
                </div>
                <div className="flex items-center space-x-1.5">
                  <div className="w-1.5 h-1.5 bg-accent rounded-full" />
                  <span className="text-steel/70">Error Auto-Reported</span>
                </div>
                <div className="text-steel/60">
                  Support: support@lever.finance
                </div>
              </div>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

export default ErrorBoundary;
