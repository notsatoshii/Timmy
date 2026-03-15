import React, { useState } from 'react';

/**
 * Test component to verify error boundaries are working
 * This component can be temporarily added to test error handling
 */
const ErrorBoundaryTest: React.FC = () => {
  const [shouldThrow, setShouldThrow] = useState(false);

  if (shouldThrow) {
    throw new Error('Test error for error boundary verification');
  }

  return (
    <div className="p-4 border border-yellow-300 bg-yellow-50 rounded-lg">
      <h3 className="text-lg font-medium text-yellow-800 mb-2">Error Boundary Test</h3>
      <p className="text-yellow-700 mb-4">
        Click the button below to trigger an error and test the error boundary.
      </p>
      <button
        onClick={() => setShouldThrow(true)}
        className="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 transition-colors"
      >
        Trigger Error
      </button>
    </div>
  );
};

export default ErrorBoundaryTest;