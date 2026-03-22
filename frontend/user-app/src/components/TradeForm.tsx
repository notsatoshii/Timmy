import React, { useState } from 'react';
import { useReadContract } from 'wagmi';
import { useWallet } from '../hooks/useWallet';
import { CONTRACT_ADDRESSES, formatUsdt } from '../config/contracts';
import { LEVERAGE_MODEL_ABI, ACCOUNT_MANAGER_ABI } from '../config/abis';

interface TradeFormProps {
  marketId: string;
  marketName: string;
  currentPrice?: number;
  onTradeSelect?: (marketId: string, marketName: string, direction: 'long' | 'short') => void;
  compact?: boolean;
}

const TradeForm: React.FC<TradeFormProps> = ({ marketId, marketName, currentPrice, onTradeSelect, compact }) => {
  const { address, isConnected } = useWallet();
  const [direction, setDirection] = useState<'long' | 'short'>('long');
  const [collateral, setCollateral] = useState('');
  const [leverage, setLeverage] = useState('5');

  const marketIdHex = marketId as `0x${string}`;

  const { data: maxLeverageRaw } = useReadContract({
    address: CONTRACT_ADDRESSES.leverageModel,
    abi: LEVERAGE_MODEL_ABI,
    functionName: 'getEffectiveMaxLeverage',
    args: [marketIdHex],
    query: { enabled: !!marketId },
  });

  const { data: accountBalance } = useReadContract({
    address: CONTRACT_ADDRESSES.accountManager,
    abi: ACCOUNT_MANAGER_ABI,
    functionName: 'getBalance',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const maxLeverage = maxLeverageRaw ? Number(maxLeverageRaw) / 1e18 : 30;
  const balance = accountBalance ? Number(accountBalance) / 1e6 : 0;
  const collateralNum = parseFloat(collateral) || 0;
  const leverageNum = parseFloat(leverage) || 1;
  const notional = collateralNum * leverageNum;

  const handleSubmit = () => {
    if (onTradeSelect) {
      onTradeSelect(marketId, marketName, direction);
    }
  };

  return (
    <div className={`${compact ? '' : 'lever-card'}`}>
      <h3 className="text-sm font-semibold text-ivory mb-4 uppercase tracking-wider">Open Position</h3>

      {/* Direction */}
      <div className="flex space-x-2 mb-4">
        <button
          onClick={() => setDirection('long')}
          className={`flex-1 py-2 rounded-lg text-sm font-semibold transition-all ${
            direction === 'long'
              ? 'bg-accent/15 text-accent border border-accent/40'
              : 'bg-surface-1 text-steel border border-border hover:text-ivory'
          }`}
        >
          Long
        </button>
        <button
          onClick={() => setDirection('short')}
          className={`flex-1 py-2 rounded-lg text-sm font-semibold transition-all ${
            direction === 'short'
              ? 'bg-danger/15 text-danger border border-danger/40'
              : 'bg-surface-1 text-steel border border-border hover:text-ivory'
          }`}
        >
          Short
        </button>
      </div>

      {/* Collateral */}
      <div className="mb-3">
        <label className="text-[11px] uppercase tracking-wider text-steel font-medium mb-1 block">
          Collateral (USDT)
        </label>
        <input
          type="number"
          value={collateral}
          onChange={(e) => setCollateral(e.target.value)}
          placeholder="0.00"
          className="w-full bg-[#0c0d14] border border-border rounded-lg px-3 py-2.5 text-ivory font-mono text-sm focus:border-accent/30 focus:ring-1 focus:ring-accent/20 outline-none transition-all"
        />
        {balance > 0 && (
          <p className="text-[10px] text-steel mt-1">Balance: ${balance.toFixed(2)}</p>
        )}
      </div>

      {/* Leverage */}
      <div className="mb-3">
        <label className="text-[11px] uppercase tracking-wider text-steel font-medium mb-1 block">
          Leverage ({leverage}x / {maxLeverage.toFixed(1)}x max)
        </label>
        <input
          type="range"
          min="1"
          max={maxLeverage}
          step="0.5"
          value={leverage}
          onChange={(e) => setLeverage(e.target.value)}
          className="w-full accent-[#E6FF2B]"
        />
        <div className="flex justify-between text-[10px] text-steel mt-0.5">
          <span>1x</span>
          <span>{maxLeverage.toFixed(0)}x</span>
        </div>
      </div>

      {/* Position Details */}
      <div className="lever-inset mb-4 space-y-1.5">
        <div className="flex justify-between text-xs">
          <span className="text-steel">Notional</span>
          <span className="text-ivory font-mono">${notional.toFixed(2)}</span>
        </div>
        {currentPrice !== undefined && (
          <div className="flex justify-between text-xs">
            <span className="text-steel">Entry Price</span>
            <span className="text-ivory font-mono">{(currentPrice * 100).toFixed(1)}¢</span>
          </div>
        )}
        <div className="flex justify-between text-xs">
          <span className="text-steel">Direction</span>
          <span className={direction === 'long' ? 'text-accent' : 'text-danger'}>{direction.toUpperCase()}</span>
        </div>
      </div>

      {/* Submit */}
      <button
        onClick={handleSubmit}
        disabled={!collateral || collateralNum <= 0}
        className="w-full py-3 rounded-lg text-sm font-bold transition-all disabled:opacity-40 disabled:cursor-not-allowed bg-accent/10 text-accent border border-accent/30 hover:bg-accent/20 hover:shadow-[0_0_20px_rgba(230,255,43,0.08)]"
      >
        {isConnected ? 'Open Position' : 'Connect Wallet'}
      </button>
    </div>
  );
};

export default TradeForm;
