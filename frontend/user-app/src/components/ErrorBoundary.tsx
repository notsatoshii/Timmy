import React, { Component, ErrorInfo, ReactNode } from 'react';

interface Props {
  children: ReactNode;
  panelName: string;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null, errorInfo: null };
  }

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { hasError: true };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error(`Error caught in ${this.props.panelName} panel:`, error);
    console.error('Error details:', errorInfo);

    this.setState({
      error,
      errorInfo
    });
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null, errorInfo: null });
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="bg-surface-1 border border-danger/30 rounded-lg p-8 text-center">
          <div className="flex flex-col items-center space-y-4">
            <div className="w-16 h-16 bg-danger-muted rounded-full flex items-center justify-center">
              <svg className="w-8 h-8 text-danger" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.732-.833-2.5 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
              </svg>
            </div>

            <div className="space-y-2">
              <h3 className="text-lg font-semibold text-gray-100">
                {this.props.panelName} Panel Error
              </h3>
              <p className="text-gray-400 max-w-md">
                Something went wrong loading this panel. This could be due to network issues,
                contract connectivity problems, or temporary service disruption.
              </p>
            </div>

            {this.state.error && (
              <div className="mt-4 p-4 bg-surface-0 border border-border rounded text-left text-sm font-mono max-w-full overflow-auto">
                <div className="font-bold text-danger mb-2">Error Details:</div>
                <div className="text-gray-300 whitespace-pre-wrap">
                  {this.state.error.toString()}
                </div>
                {this.state.errorInfo && (
                  <div className="mt-2 text-gray-500">
                    <div className="font-bold mb-1">Stack trace:</div>
                    <div className="whitespace-pre-wrap">
                      {this.state.errorInfo.componentStack}
                    </div>
                  </div>
                )}
              </div>
            )}

            <div className="flex space-x-3">
              <button
                onClick={this.handleRetry}
                className="px-4 py-2 bg-accent text-surface-0 rounded-md hover:bg-accent-dim transition-colors font-medium"
              >
                Try Again
              </button>
              <button
                onClick={() => window.location.reload()}
                className="px-4 py-2 bg-surface-3 text-gray-300 rounded-md hover:bg-border-light transition-colors font-medium"
              >
                Refresh Page
              </button>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

export default ErrorBoundary;
