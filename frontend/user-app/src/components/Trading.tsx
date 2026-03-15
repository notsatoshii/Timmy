import React, { useState } from 'react';
import { useAccount, useWriteContract, useReadContract } from 'wagmi';
import { parseUnits } from 'viem';
import { CONTRACT_ADDRESSES, formatUsdt, parseUsdt } from '../config/contracts';
import { EXECUTION_ENGINE_ABI, ACCOUNT_MANAGER_ABI, USDT_ABI } from '../config/abis';

interface TradeForm {
  marketId: string;
  direction: 'long' | 'short';
  collateral: string;
  leverage: string;
}

const Trading: React.FC = () => {
  const { address } = useAccount();
  const [tradeForm, setTradeForm] = useState<TradeForm>({
    marketId: '',
    direction: 'long',
    collateral: '',
    leverage: '1',
  });

  const { writeContract: openPosition } = useWriteContract();
  const { writeContract: depositCollateral } = useWriteContract();
  const { writeContract: approveUsdt } = useWriteContract();

  // Read user's USDT balance
  const { data: usdtBalance } = useReadContract({
    address: CONTRACT_ADDRESSES.usdt as `0x${string}`,
    abi: USDT_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
  });

  // Read user's account balance (deposited USDT)
  const { data: accountBalance } = useReadContract({
    address: CONTRACT_ADDRESSES.accountManager as `0x${string}`,
    abi: ACCOUNT_MANAGER_ABI,
    functionName: 'getBalance',
    args: address ? [address] : undefined,
  });

  const handleInputChange = (field: keyof TradeForm, value: string) => {
    setTradeForm(prev => ({ ...prev, [field]: value }));
  };

  const handleApproveUsdt = async () => {
    if (!tradeForm.collateral) return;

    try {
      const amount = parseUsdt(tradeForm.collateral);
      await approveUsdt({
        address: CONTRACT_ADDRESSES.usdt as `0x${string}`,
        abi: USDT_ABI,
        functionName: 'approve',
        args: [CONTRACT_ADDRESSES.accountManager, amount],
      });
    } catch (error) {
      console.error('Error approving USDT:', error);
    }
  };

  const handleDeposit = async () => {
    if (!tradeForm.collateral) return;

    try {
      const amount = parseUsdt(tradeForm.collateral);
      await depositCollateral({
        address: CONTRACT_ADDRESSES.accountManager as `0x${string}`,
        abi: ACCOUNT_MANAGER_ABI,
        functionName: 'deposit',
        args: [amount],
      });
    } catch (error) {
      console.error('Error depositing collateral:', error);
    }
  };

  const handleOpenPosition = async () => {
    if (!tradeForm.marketId || !tradeForm.collateral || !tradeForm.leverage) return;

    try {
      const collateralAmount = parseUsdt(tradeForm.collateral);
      const leverage = parseUnits(tradeForm.leverage, 18);

      await openPosition({
        address: CONTRACT_ADDRESSES.executionEngine as `0x${string}`,
        abi: EXECUTION_ENGINE_ABI,
        functionName: 'openPosition',
        args: [
          tradeForm.marketId as `0x${string}`,
          tradeForm.direction === 'long',
          collateralAmount,
          leverage,
        ],
      });

      // Reset form
      setTradeForm({
        marketId: '',
        direction: 'long',
        collateral: '',
        leverage: '1',
      });
    } catch (error) {
      console.error('Error opening position:', error);
    }
  };

  const calculatePositionSize = () => {
    if (!tradeForm.collateral || !tradeForm.leverage) return '0';
    const collateral = parseFloat(tradeForm.collateral);
    const leverage = parseFloat(tradeForm.leverage);
    return (collateral * leverage).toFixed(2);
  };

  const mockMarkets = [
    { id: '0x1', name: 'Bitcoin $100K by Mar 2026' },
    { id: '0x2', name: 'US Election 2028 - Democrat Win' },
    { id: '0x3', name: 'AI Protein Folding by 2027' },
    { id: '0x4', name: 'Next Super Bowl - AFC Win' },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-gray-900">Open Position</h2>
        <p className="text-gray-600">
          Take leveraged positions on binary prediction markets
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Trading Form */}
        <div className="lg:col-span-2">
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Position Details</h3>

            <div className="space-y-4">
              {/* Market Selection */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Select Market
                </label>
                <select
                  value={tradeForm.marketId}
                  onChange={(e) => handleInputChange('marketId', e.target.value)}
                  className="w-full rounded-md border-gray-300 shadow-sm focus:border-primary-500 focus:ring-primary-500"
                >
                  <option value="">Choose a market...</option>
                  {mockMarkets.map((market) => (
                    <option key={market.id} value={market.id}>
                      {market.name}
                    </option>
                  ))}
                </select>
              </div>

              {/* Direction */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Direction
                </label>
                <div className="flex space-x-3">
                  <button
                    type="button"
                    onClick={() => handleInputChange('direction', 'long')}
                    className={`flex-1 py-2 px-4 rounded-md text-sm font-medium transition-colors ${
                      tradeForm.direction === 'long'
                        ? 'bg-success-600 text-white'
                        : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                    }`}
                  >
                    Long (Yes)
                  </button>
                  <button
                    type="button"
                    onClick={() => handleInputChange('direction', 'short')}
                    className={`flex-1 py-2 px-4 rounded-md text-sm font-medium transition-colors ${
                      tradeForm.direction === 'short'
                        ? 'bg-danger-600 text-white'
                        : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                    }`}
                  >
                    Short (No)
                  </button>
                </div>
              </div>

              {/* Collateral Amount */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Collateral Amount (USDT)
                </label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={tradeForm.collateral}
                  onChange={(e) => handleInputChange('collateral', e.target.value)}
                  placeholder="0.00"
                  className="w-full rounded-md border-gray-300 shadow-sm focus:border-primary-500 focus:ring-primary-500"
                />
                <p className="text-xs text-gray-500 mt-1">
                  Wallet Balance: {usdtBalance ? formatUsdt(usdtBalance) : '0'} USDT
                </p>
              </div>

              {/* Leverage */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Leverage: {tradeForm.leverage}x
                </label>
                <input
                  type="range"
                  min="1"
                  max="30"
                  step="0.5"
                  value={tradeForm.leverage}
                  onChange={(e) => handleInputChange('leverage', e.target.value)}
                  className="w-full"
                />
                <div className="flex justify-between text-xs text-gray-500 mt-1">
                  <span>1x</span>
                  <span>15x</span>
                  <span>30x</span>
                </div>
              </div>
            </div>

            <div className="mt-6 pt-4 border-t border-gray-200">
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-600">Position Size:</span>
                  <span className="font-medium">{calculatePositionSize()} USDT</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">Liquidation Risk:</span>
                  <span className={`font-medium ${
                    parseFloat(tradeForm.leverage) > 10 ? 'text-danger-600' : 'text-success-600'
                  }`}>
                    {parseFloat(tradeForm.leverage) > 10 ? 'High' : 'Low'}
                  </span>
                </div>
              </div>
            </div>

            <div className="mt-6 space-y-3">
              {/* Action Buttons */}
              {!accountBalance || accountBalance < parseUsdt(tradeForm.collateral || '0') ? (
                <div className="space-y-2">
                  <button
                    onClick={handleApproveUsdt}
                    disabled={!tradeForm.collateral}
                    className="w-full bg-primary-600 text-white py-3 px-4 rounded-md font-medium hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    1. Approve USDT
                  </button>
                  <button
                    onClick={handleDeposit}
                    disabled={!tradeForm.collateral}
                    className="w-full bg-primary-600 text-white py-3 px-4 rounded-md font-medium hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    2. Deposit Collateral
                  </button>
                </div>
              ) : (
                <button
                  onClick={handleOpenPosition}
                  disabled={!tradeForm.marketId || !tradeForm.collateral}
                  className="w-full bg-primary-600 text-white py-3 px-4 rounded-md font-medium hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Open Position
                </button>
              )}
            </div>
          </div>
        </div>

        {/* Account Info */}
        <div className="space-y-6">
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Account</h3>
            <div className="space-y-3">
              <div className="flex justify-between">
                <span className="text-gray-600">USDT Balance:</span>
                <span className="font-medium">
                  {usdtBalance ? formatUsdt(usdtBalance) : '0'} USDT
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-600">Available Collateral:</span>
                <span className="font-medium">
                  {accountBalance ? formatUsdt(accountBalance) : '0'} USDT
                </span>
              </div>
            </div>
          </div>

          {/* Get Test USDT */}
          <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
            <h4 className="font-medium text-yellow-800 mb-2">Need Test USDT?</h4>
            <p className="text-sm text-yellow-700 mb-3">
              Get free test USDT for Base Sepolia testnet
            </p>
            <button
              onClick={() => {
                // Call USDT faucet
                approveUsdt({
                  address: CONTRACT_ADDRESSES.usdt as `0x${string}`,
                  abi: USDT_ABI,
                  functionName: 'faucet',
                  args: [],
                });
              }}
              className="w-full bg-yellow-600 text-white py-2 px-3 rounded-md text-sm font-medium hover:bg-yellow-700"
            >
              Get 10,000 USDT
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Trading;