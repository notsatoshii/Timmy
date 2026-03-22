import React from 'react';

interface SkeletonProps {
  className?: string;
  width?: string;
  height?: string;
  variant?: 'text' | 'rectangular' | 'circular';
}

const Skeleton: React.FC<SkeletonProps> = ({
  className = '',
  width,
  height,
  variant = 'rectangular'
}) => {
  const baseClasses = 'animate-pulse bg-surface-3';

  const variantClasses = {
    text: 'rounded',
    rectangular: 'rounded-md',
    circular: 'rounded-full',
  };

  const style = {
    width: width || undefined,
    height: height || undefined,
  };

  return (
    <div
      className={`${baseClasses} ${variantClasses[variant]} ${className}`}
      style={style}
    />
  );
};

export default Skeleton;
