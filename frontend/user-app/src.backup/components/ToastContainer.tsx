import React from 'react';
import { createPortal } from 'react-dom';
import Toast, { ToastData } from './Toast';

interface ToastContainerProps {
  toasts: ToastData[];
  onDismiss: (id: string) => void;
}

const ToastContainer: React.FC<ToastContainerProps> = ({ toasts, onDismiss }) => {
  if (toasts.length === 0) return null;

  return createPortal(
    <div className="fixed top-4 right-4 z-50 flex flex-col space-y-3 max-w-sm w-full">
      {toasts.map((toast) => (
        <Toast
          key={toast.id}
          toast={toast}
          onDismiss={onDismiss}
        />
      ))}
    </div>,
    document.body
  );
};

export default ToastContainer;