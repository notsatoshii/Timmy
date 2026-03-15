import React, { createContext, useContext, useState, useCallback, ReactNode } from 'react';
import { ToastData } from '../components/Toast';
import ToastContainer from '../components/ToastContainer';

interface NotificationContextType {
  showToast: (toast: Omit<ToastData, 'id'>) => string;
  dismissToast: (id: string) => void;
  showTradeConfirmation: (type: 'open' | 'close', marketName: string, txHash?: string) => void;
  showLiquidationWarning: (marginPercent: number, marketName: string) => void;
  showErrorToast: (title: string, message?: string) => void;
  showSuccessToast: (title: string, message?: string, txHash?: string) => void;
  showWarningToast: (title: string, message?: string) => void;
}

const NotificationContext = createContext<NotificationContextType | null>(null);

export const useNotifications = (): NotificationContextType => {
  const context = useContext(NotificationContext);
  if (!context) {
    throw new Error('useNotifications must be used within a NotificationProvider');
  }
  return context;
};

interface NotificationProviderProps {
  children: ReactNode;
}

export const NotificationProvider: React.FC<NotificationProviderProps> = ({ children }) => {
  const [toasts, setToasts] = useState<ToastData[]>([]);

  const generateId = (): string => {
    return `toast-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  };

  const showToast = useCallback((toast: Omit<ToastData, 'id'>): string => {
    const id = generateId();
    const newToast: ToastData = {
      ...toast,
      id,
      duration: toast.duration ?? (toast.type === 'error' ? 8000 : 5000), // Errors stay longer
    };

    setToasts(prev => [...prev, newToast]);
    return id;
  }, []);

  const dismissToast = useCallback((id: string): void => {
    setToasts(prev => prev.filter(toast => toast.id !== id));
  }, []);

  const showTradeConfirmation = useCallback((
    type: 'open' | 'close',
    marketName: string,
    txHash?: string
  ): void => {
    const isOpen = type === 'open';
    showToast({
      type: 'success',
      title: `Position ${isOpen ? 'Opened' : 'Closed'}`,
      message: `${marketName} position ${isOpen ? 'successfully opened' : 'closed and settled'}`,
      txHash,
      duration: 6000,
      action: txHash ? {
        label: 'View on Explorer',
        onClick: () => window.open(`https://sepolia.basescan.org/tx/${txHash}`, '_blank')
      } : undefined
    });
  }, [showToast]);

  const showLiquidationWarning = useCallback((
    marginPercent: number,
    marketName: string
  ): void => {
    const isEmergency = marginPercent < 110; // Very close to liquidation
    const severity = isEmergency ? 'error' : 'warning';

    showToast({
      type: severity,
      title: isEmergency ? 'Liquidation Risk - Immediate Action Required' : 'Margin Warning',
      message: `${marketName} position at ${marginPercent.toFixed(1)}% margin. ${
        isEmergency
          ? 'Add collateral or close position immediately to avoid liquidation.'
          : 'Consider adding collateral or reducing position size.'
      }`,
      duration: isEmergency ? 12000 : 8000, // Emergency warnings stay longer
      action: {
        label: isEmergency ? 'Go to Position' : 'View Position',
        onClick: () => {
          // Navigate to positions tab - will be handled by parent component
          const event = new CustomEvent('navigate-to-positions');
          window.dispatchEvent(event);
        }
      }
    });
  }, [showToast]);

  const showErrorToast = useCallback((title: string, message?: string): void => {
    showToast({
      type: 'error',
      title,
      message,
      duration: 8000
    });
  }, [showToast]);

  const showSuccessToast = useCallback((
    title: string,
    message?: string,
    txHash?: string
  ): void => {
    showToast({
      type: 'success',
      title,
      message,
      txHash,
      duration: 5000,
      action: txHash ? {
        label: 'View Transaction',
        onClick: () => window.open(`https://sepolia.basescan.org/tx/${txHash}`, '_blank')
      } : undefined
    });
  }, [showToast]);

  const showWarningToast = useCallback((title: string, message?: string): void => {
    showToast({
      type: 'warning',
      title,
      message,
      duration: 6000
    });
  }, [showToast]);

  const contextValue: NotificationContextType = {
    showToast,
    dismissToast,
    showTradeConfirmation,
    showLiquidationWarning,
    showErrorToast,
    showSuccessToast,
    showWarningToast,
  };

  return (
    <NotificationContext.Provider value={contextValue}>
      {children}
      <ToastContainer toasts={toasts} onDismiss={dismissToast} />
    </NotificationContext.Provider>
  );
};

export default NotificationProvider;