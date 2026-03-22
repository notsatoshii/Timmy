import React, { useEffect, useState } from 'react';

export interface ToastData {
  id: string;
  type: 'success' | 'error' | 'warning' | 'info';
  title: string;
  message?: string;
  duration?: number;
  action?: {
    label: string;
    onClick: () => void;
  };
  txHash?: string;
}

interface ToastProps {
  toast: ToastData;
  onDismiss: (id: string) => void;
}

const Toast: React.FC<ToastProps> = ({ toast, onDismiss }) => {
  const [isVisible, setIsVisible] = useState(false);
  const [isLeaving, setIsLeaving] = useState(false);

  useEffect(() => {
    // Animate in
    const timer = setTimeout(() => setIsVisible(true), 50);
    return () => clearTimeout(timer);
  }, []);

  useEffect(() => {
    if (toast.duration && toast.duration > 0) {
      const timer = setTimeout(() => {
        handleDismiss();
      }, toast.duration);
      return () => clearTimeout(timer);
    }
  }, [toast.duration]);

  const handleDismiss = () => {
    setIsLeaving(true);
    setTimeout(() => {
      onDismiss(toast.id);
    }, 300);
  };

  const getIcon = () => {
    switch (toast.type) {
      case 'success':
        return (
          <svg className="w-5 h-5 text-accent" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        );
      case 'error':
        return (
          <svg className="w-5 h-5 text-danger" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        );
      case 'warning':
        return (
          <svg className="w-5 h-5 text-warning" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.732-.833-2.464 0L5.35 16.5c-.77.833.192 2.5 1.732 2.5z" />
          </svg>
        );
      case 'info':
        return (
          <svg className="w-5 h-5 text-purple" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        );
      default:
        return null;
    }
  };

  const getColorClasses = () => {
    switch (toast.type) {
      case 'success':
        return 'bg-accent-muted border-accent/20 text-accent';
      case 'error':
        return 'bg-danger-muted border-danger/20 text-danger';
      case 'warning':
        return 'bg-warning-muted border-warning/20 text-warning';
      case 'info':
        return 'bg-purple-muted border-purple/20 text-purple';
      default:
        return 'bg-surface-2 border-border text-gray-300';
    }
  };

  const formatTxHash = (hash: string): string => {
    return `${hash.slice(0, 6)}...${hash.slice(-4)}`;
  };

  return (
    <div
      className={`
        flex items-start space-x-3 p-4 rounded-lg border shadow-lg backdrop-blur-sm
        transition-all duration-300 ease-out
        ${getColorClasses()}
        ${isVisible && !isLeaving ? 'translate-x-0 opacity-100' : 'translate-x-full opacity-0'}
        ${isLeaving ? '-translate-x-2 opacity-0 scale-95' : ''}
      `}
    >
      {/* Icon */}
      <div className="flex-shrink-0 mt-0.5">
        {getIcon()}
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center justify-between">
          <h4 className="text-sm font-semibold text-gray-100">
            {toast.title}
          </h4>
          <button
            onClick={handleDismiss}
            className="ml-2 text-gray-400 hover:text-gray-200 transition-colors"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {toast.message && (
          <p className="mt-1 text-sm text-gray-300">
            {toast.message}
          </p>
        )}

        {/* Transaction Hash */}
        {toast.txHash && (
          <div className="mt-2 flex items-center space-x-2">
            <span className="text-xs text-gray-500">Transaction:</span>
            <a
              href={`https://sepolia.basescan.org/tx/${toast.txHash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs font-mono text-accent hover:text-accent-dim transition-colors"
            >
              {formatTxHash(toast.txHash)}
            </a>
            <svg className="w-3 h-3 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
            </svg>
          </div>
        )}

        {/* Action Button */}
        {toast.action && (
          <div className="mt-3">
            <button
              onClick={toast.action.onClick}
              className="text-xs font-medium text-accent hover:text-accent-dim transition-colors"
            >
              {toast.action.label}
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default Toast;