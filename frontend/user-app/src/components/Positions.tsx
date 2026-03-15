import React, { useState, useEffect, useMemo } from 'react';
import { useAccount, useReadContract, useWriteContract } from 'wagmi';
import { CONTRACT_ADDRESSES, formatWad } from '../config/contracts';
import { POSITION_MANAGER_ABI, EXECUTION_ENGINE_ABI } from '../config/abis';

interface Position {
  id: string;
  marketId: string;
  marketName: string;
  isLong: boolean;
  collateralAmount: bigint;
  positionSize: bigint;
  entryPrice: bigint;
  leverage: bigint;
  currentPrice: bigint;
  pnl: bigint;
  pnlPercentage: number;
  liquidationPrice: bigint;
  timeToResolution: string;
}

const Positions: React.FC = () => {
  const { address } = useAccount();
  const [positions, setPositions] = useState<Position[]>([]);
  const [selectedPosition, setSelectedPosition] = useState<string | null>(null);
  const [closeAmount, setCloseAmount] = useState('');

  const { writeContract: closePosition } = useWriteContract();

  // Read user's position IDs
  const { data: positionIds } = useReadContract({
    address: CONTRACT_ADDRESSES.positionManager as `0x${string}`,
    abi: POSITION_MANAGER_ABI,
    functionName: 'getUserPositions',
    args: address ? [address] : undefined,
  });

  // Mock positions for demo purposes since we might not have real positions yet
  const mockPositions: Position[] = useMemo(() => [
    {
      id: '1',
      marketId: '0x1',
      marketName: 'Bitcoin $100K by Mar 2026',
      isLong: true,
      collateralAmount: BigInt('1000000000000000000'),
      positionSize: BigInt('5000000000000000000000'),
      entryPrice: BigInt('650000000000000000'),
      leverage: BigInt('5000000000000000000'),
      currentPrice: BigInt('680000000000000000'),
      pnl: BigInt('230000000000000000000'),
      pnlPercentage: 23.0,
      liquidationPrice: BigInt('520000000000000000'),
      timeToResolution: '367d 14h',
    },
    {
      id: '2',
      marketId: '0x2',
      marketName: 'US Election 2028 - Democrat Win',
      isLong: false,
      collateralAmount: BigInt('500000000000000000'),
      positionSize: BigInt('2500000000000000000000'),
      entryPrice: BigInt('480000000000000000'),
      leverage: BigInt('5000000000000000000'),
      currentPrice: BigInt('450000000000000000'),
      pnl: BigInt('75000000000000000000'),
      pnlPercentage: 15.0,
      liquidationPrice: BigInt('580000000000000000'),
      timeToResolution: '1095d 8h',
    },
  ], []);

  useEffect(() => {
    if (address) {
      setPositions(mockPositions);
    } else {
      setPositions([]);
    }
  }, [address, positionIds, mockPositions]);

  const handleClosePosition = async (positionId: string) => {
    try {
      await closePosition({
        address: CONTRACT_ADDRESSES.executionEngine as `0x${string}`,
        abi: EXECUTION_ENGINE_ABI,
        functionName: 'closePosition',
        args: [BigInt(positionId)],
      });
      setSelectedPosition(null);
      setCloseAmount('');
    } catch (error) {
      console.error('Error closing position:', error);
    }
  };

  const getPnlColor = (pnl: bigint): string => {
    if (pnl > 0) return 'text-success-600';
    if (pnl < 0) return 'text-danger-600';
    return 'text-gray-600';
  };

  const getLeverageColor = (leverage: bigint): string => {
    const leverageNumber = Number(leverage) / 1e18;
    if (leverageNumber > 10) return 'text-danger-600';
    if (leverageNumber > 5) return 'text-yellow-600';
    return 'text-success-600';
  };

  const formatPrice = (price: bigint): string => {
    return `${(Number(price) / 1e18 * 100).toFixed(1)}¢`;
  };

  const calculateLiquidationDistance = (currentPrice: bigint, liquidationPrice: bigint, isLong: boolean): number => {
    const current = Number(currentPrice) / 1e18;
    const liquidation = Number(liquidationPrice) / 1e18;
    if (isLong) {
      return ((current - liquidation) / current) * 100;
    } else {
      return ((liquidation - current) / current) * 100;
    }
  };

  const totalPnl = positions.reduce((sum, pos) => sum + Number(pos.pnl) / 1e18, 0);
  const totalCollateral = positions.reduce((sum, pos) => sum + Number(pos.collateralAmount) / 1e18, 0);
  const totalPositionValue = positions.reduce((sum, pos) => sum + Number(pos.positionSize) / 1e18, 0);

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-gray-900">Your Positions</h2>
        <p className="text-gray-600">
          Monitor and manage your active leveraged positions
        </p>
      </div>

      {/* Portfolio Summary */}
      {positions.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 className="text-sm font-medium text-gray-500 mb-2">Total PnL</h3>
            <p className={`text-2xl font-bold ${getPnlColor(BigInt(Math.floor(totalPnl * 1e18)))}`}>
              {totalPnl >= 0 ? '+' : ''}${totalPnl.toFixed(2)}
            </p>
            <p className="text-sm text-gray-600 mt-1">
              {totalPnl >= 0 ? '+' : ''}{((totalPnl / totalCollateral) * 100).toFixed(2)}%
            </p>
          </div>
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 className="text-sm font-medium text-gray-500 mb-2">Total Collateral</h3>
            <p className="text-2xl font-bold text-gray-900">${totalCollateral.toFixed(2)}</p>
            <p className="text-sm text-gray-600 mt-1">USDT</p>
          </div>
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 className="text-sm font-medium text-gray-500 mb-2">Total Position Value</h3>
            <p className="text-2xl font-bold text-gray-900">${totalPositionValue.toFixed(2)}</p>
            <p className="text-sm text-gray-600 mt-1">Notional value</p>
          </div>
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 className="text-sm font-medium text-gray-500 mb-2">Active Positions</h3>
            <p className="text-2xl font-bold text-gray-900">{positions.length}</p>
            <p className="text-sm text-gray-600 mt-1">Open positions</p>
          </div>
        </div>
      )}

      {/* Positions List */}
      <div className="space-y-4">
        {positions.map((position) => (
          <div key={position.id} className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <div className="flex items-start justify-between">
              <div className="flex-1 min-w-0">
                <div className="flex items-center space-x-3 mb-3">
                  <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                    position.isLong ? 'bg-success-100 text-success-800' : 'bg-danger-100 text-danger-800'
                  }`}>
                    {position.isLong ? 'LONG' : 'SHORT'}
                  </span>
                  <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${getLeverageColor(position.leverage)} bg-gray-100`}>
                    {(Number(position.leverage) / 1e18).toFixed(1)}x
                  </span>
                </div>

                <h3 className="text-lg font-semibold text-gray-900 mb-4">{position.marketName}</h3>

                <div className="grid grid-cols-2 md:grid-cols-6 gap-4 text-sm">
                  <div>
                    <p className="text-gray-500">Collateral</p>
                    <p className="font-semibold text-gray-900">${formatWad(position.collateralAmount)}</p>
                  </div>
                  <div>
                    <p className="text-gray-500">Position Size</p>
                    <p className="font-semibold text-gray-900">${formatWad(position.positionSize)}</p>
                  </div>
                  <div>
                    <p className="text-gray-500">Entry Price</p>
                    <p className="font-semibold text-gray-900">{formatPrice(position.entryPrice)}</p>
                  </div>
                  <div>
                    <p className="text-gray-500">Current Price</p>
                    <p className="font-semibold text-gray-900">{formatPrice(position.currentPrice)}</p>
                  </div>
                  <div>
                    <p className="text-gray-500">PnL</p>
                    <p className={`font-semibold ${getPnlColor(position.pnl)}`}>
                      {position.pnl > 0 ? '+' : ''}${formatWad(position.pnl)}
                    </p>
                    <p className={`text-xs ${getPnlColor(position.pnl)}`}>
                      {position.pnl > 0 ? '+' : ''}{position.pnlPercentage.toFixed(2)}%
                    </p>
                  </div>
                  <div>
                    <p className="text-gray-500">Resolution</p>
                    <p className="font-semibold text-gray-900">{position.timeToResolution}</p>
                  </div>
                </div>

                {/* Risk Metrics */}
                <div className="mt-4 pt-4 border-t border-gray-200">
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
                    <div>
                      <p className="text-gray-500">Liquidation Price</p>
                      <p className="font-semibold text-gray-900">{formatPrice(position.liquidationPrice)}</p>
                    </div>
                    <div>
                      <p className="text-gray-500">Distance to Liquidation</p>
                      <p className={`font-semibold ${
                        calculateLiquidationDistance(position.currentPrice, position.liquidationPrice, position.isLong) > 20
                          ? 'text-success-600'
                          : calculateLiquidationDistance(position.currentPrice, position.liquidationPrice, position.isLong) > 10
                          ? 'text-yellow-600' : 'text-danger-600'
                      }`}>
                        {calculateLiquidationDistance(position.currentPrice, position.liquidationPrice, position.isLong).toFixed(1)}%
                      </p>
                    </div>
                    <div>
                      <p className="text-gray-500">Health Status</p>
                      <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
                        calculateLiquidationDistance(position.currentPrice, position.liquidationPrice, position.isLong) > 20
                          ? 'bg-success-100 text-success-800'
                          : calculateLiquidationDistance(position.currentPrice, position.liquidationPrice, position.isLong) > 10
                          ? 'bg-yellow-100 text-yellow-800' : 'bg-danger-100 text-danger-800'
                      }`}>
                        {calculateLiquidationDistance(position.currentPrice, position.liquidationPrice, position.isLong) > 20
                          ? 'Healthy'
                          : calculateLiquidationDistance(position.currentPrice, position.liquidationPrice, position.isLong) > 10
                          ? 'Warning' : 'At Risk'}
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              {/* Actions */}
              <div className="ml-6 flex-shrink-0">
                {selectedPosition === position.id ? (
                  <div className="space-y-3 w-48">
                    <input
                      type="number"
                      step="0.01"
                      placeholder="Amount to close"
                      value={closeAmount}
                      onChange={(e) => setCloseAmount(e.target.value)}
                      className="w-full px-3 py-2 text-sm border border-gray-300 rounded-md focus:ring-primary-500 focus:border-primary-500"
                    />
                    <div className="flex space-x-2">
                      <button
                        onClick={() => handleClosePosition(position.id)}
                        disabled={!closeAmount}
                        className="flex-1 bg-danger-600 text-white px-3 py-2 rounded-md text-sm font-medium hover:bg-danger-700 disabled:opacity-50"
                      >
                        Close
                      </button>
                      <button
                        onClick={() => { setSelectedPosition(null); setCloseAmount(''); }}
                        className="flex-1 bg-gray-300 text-gray-700 px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-400"
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className="space-y-2">
                    <button
                      onClick={() => setSelectedPosition(position.id)}
                      className="w-full bg-primary-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-primary-700"
                    >
                      Manage
                    </button>
                    <button
                      onClick={() => { setSelectedPosition(position.id); setCloseAmount(formatWad(position.collateralAmount)); }}
                      className="w-full bg-gray-100 text-gray-700 px-4 py-2 rounded-md text-sm font-medium hover:bg-gray-200"
                    >
                      Close All
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Empty State */}
      {positions.length === 0 && (
        <div className="text-center py-12">
          <div className="w-16 h-16 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg className="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
            </svg>
          </div>
          <h3 className="text-lg font-medium text-gray-900 mb-2">No Positions</h3>
          <p className="text-gray-600 mb-4">You don't have any active positions yet.</p>
          <p className="text-sm text-gray-500">Go to the Trading tab to open your first leveraged position</p>
        </div>
      )}
    </div>
  );
};

export default Positions;
