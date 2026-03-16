import React, { useState } from 'react';
import { useWallet } from '../hooks/useWallet';
import { useTradeHistory, TradeHistoryEntry } from '../hooks/useTradeHistory';
import { formatWad } from '../config/contracts';

interface TradeHistoryProps {
  userOnly?: boolean;
}

const TradeHistory: React.FC<TradeHistoryProps> = ({ userOnly = false }) => {
  const { address } = useWallet();
  const [showAllTrades, setShowAllTrades] = useState(!userOnly);

  const { history, isLoading, error } = useTradeHistory({
    enabled: true,
    limit: 50,
    userOnly: showAllTrades ? undefined : address,
  });

  const formatPrice = (price: bigint): string => {
    return `${(Number(price) / 1e18 * 100).toFixed(1)}c`;
  };

  const formatPnl = (value: bigint): string => {
    const num = Number(value) / 1e18;
    const prefix = num >= 0 ? '+' : '';
    return `${prefix}$${num.toFixed(2)}`;
  };

  const getPnlColor = (value: bigint): string => {
    if (value > BigInt(0)) return 'text-accent';
    if (value < BigInt(0)) return 'text-danger';
    return 'text-gray-500';
  };

  const formatLeverage = (leverage: bigint): string => {
    return `${(Number(leverage) / 1e18).toFixed(1)}x`;
  };

  const formatAddress = (addr: string): string => {
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
  };

  const formatTimestamp = (timestamp: bigint): string => {
    const date = new Date(Number(timestamp) * 1000);
    return date.toLocaleString();
  };

  const renderTradeEntry = (trade: TradeHistoryEntry) => {
    const isOwner = address && trade.owner.toLowerCase() === address.toLowerCase();

    return (
      <div
        key={trade.id}
        className={`border rounded-lg p-4 transition-colors ${
          isOwner ? 'bg-purple-muted border-purple/20' : 'bg-surface-1 border-border'
        }`}
      >
        <div className="flex items-start justify-between">
          <div className="flex-1 min-w-0">
            <div className="flex items-center space-x-3 mb-2">
              <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-bold ${
                trade.type === 'opened'
                  ? 'bg-purple-muted text-purple border border-purple/20'
                  : 'bg-surface-3 text-gray-400 border border-border'
              }`}>
                {trade.type === 'opened' ? 'OPENED' : 'CLOSED'}
              </span>

              <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-bold ${
                trade.isLong
                  ? 'bg-accent-muted text-accent border border-accent/20'
                  : 'bg-danger-muted text-danger border border-danger/20'
              }`}>
                {trade.isLong ? 'LONG' : 'SHORT'}
              </span>

              {trade.leverage && (
                <span className="inline-flex items-center px-2 py-1 rounded text-xs font-bold font-mono bg-surface-3 text-gray-400 border border-border">
                  {formatLeverage(trade.leverage)}
                </span>
              )}

              {isOwner && (
                <span className="inline-flex items-center px-2 py-1 rounded text-xs font-bold bg-purple-muted text-purple border border-purple/20">
                  YOUR TRADE
                </span>
              )}
            </div>

            <h3 className="text-lg font-semibold text-gray-100 mb-2">{trade.marketName}</h3>

            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div>
                <p className="text-gray-500 text-xs uppercase tracking-wide">Position ID</p>
                <p className="font-semibold font-mono text-gray-200">#{trade.positionId.toString()}</p>
              </div>

              <div>
                <p className="text-gray-500 text-xs uppercase tracking-wide">Trader</p>
                <p className="font-semibold font-mono text-gray-200">{formatAddress(trade.owner)}</p>
              </div>

              {trade.type === 'opened' && trade.collateral && (
                <div>
                  <p className="text-gray-500 text-xs uppercase tracking-wide">Collateral</p>
                  <p className="font-semibold font-mono text-gray-200">${formatWad(trade.collateral)}</p>
                </div>
              )}

              {trade.type === 'opened' && trade.positionSize && (
                <div>
                  <p className="text-gray-500 text-xs uppercase tracking-wide">Notional</p>
                  <p className="font-semibold font-mono text-gray-200">${formatWad(trade.positionSize)}</p>
                </div>
              )}

              {trade.entryPrice && (
                <div>
                  <p className="text-gray-500 text-xs uppercase tracking-wide">Entry Price</p>
                  <p className="font-semibold font-mono text-gray-200">{formatPrice(trade.entryPrice)}</p>
                </div>
              )}

              {trade.exitPrice && (
                <div>
                  <p className="text-gray-500 text-xs uppercase tracking-wide">Exit Price</p>
                  <p className="font-semibold font-mono text-gray-200">{formatPrice(trade.exitPrice)}</p>
                </div>
              )}

              {trade.realizedPnL !== undefined && (
                <div>
                  <p className="text-gray-500 text-xs uppercase tracking-wide">Realized PnL</p>
                  <p className={`font-semibold font-mono ${getPnlColor(trade.realizedPnL)}`}>
                    {formatPnl(trade.realizedPnL)}
                  </p>
                </div>
              )}

              <div>
                <p className="text-gray-500 text-xs uppercase tracking-wide">Time</p>
                <p className="font-semibold text-gray-200">{formatTimestamp(trade.timestamp)}</p>
              </div>
            </div>

            {trade.type === 'closed' && (
              <div className="mt-3 pt-3 border-t border-border">
                <div className="flex space-x-6 text-xs text-gray-500">
                  {trade.borrowFeesPaid && (
                    <span>Borrow fees: <span className="font-mono text-danger">-${formatWad(trade.borrowFeesPaid)}</span></span>
                  )}
                  {trade.fundingPaid !== undefined && (
                    <span>Funding: <span className={`font-mono ${trade.fundingPaid >= BigInt(0) ? 'text-accent' : 'text-danger'}`}>
                      {formatPnl(trade.fundingPaid)}
                    </span></span>
                  )}
                </div>
              </div>
            )}
          </div>

          <div className="ml-4 flex-shrink-0">
            <a
              href={`https://sepolia.basescan.org/tx/${trade.txHash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-purple hover:text-purple-dim underline"
            >
              View TX
            </a>
          </div>
        </div>
      </div>
    );
  };

  if (error) {
    return (
      <div className="bg-danger-muted border border-danger/20 rounded-lg p-4">
        <p className="text-danger font-medium">Failed to load trade history</p>
        <p className="text-gray-400 text-sm mt-1">{error}</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-gray-100">Recent Trades</h3>
          <p className="text-sm text-gray-500">
            Recent position opens and closes across all markets
          </p>
        </div>

        {address && (
          <div className="flex items-center space-x-2">
            <label className="text-sm text-gray-500">Show:</label>
            <select
              value={showAllTrades ? 'all' : 'mine'}
              onChange={(e) => setShowAllTrades(e.target.value === 'all')}
              className="text-sm border border-border rounded px-2 py-1 bg-surface-3 text-gray-200"
            >
              <option value="all">All trades</option>
              <option value="mine">My trades only</option>
            </select>
          </div>
        )}
      </div>

      {isLoading && (
        <div className="text-center py-8">
          <div className="animate-spin w-6 h-6 border-2 border-accent border-t-transparent rounded-full mx-auto mb-2" />
          <p className="text-sm text-gray-500">Loading recent trades...</p>
        </div>
      )}

      {!isLoading && (
        <div className="space-y-3">
          {history.length > 0 ? (
            history.map(renderTradeEntry)
          ) : (
            <div className="text-center py-8">
              <div className="w-12 h-12 bg-surface-3 rounded-full flex items-center justify-center mx-auto mb-3">
                <svg className="w-6 h-6 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
                </svg>
              </div>
              <h3 className="text-sm font-medium text-gray-300">No recent trades</h3>
              <p className="text-sm text-gray-500 mt-1">
                {showAllTrades ? 'No trades found in recent blocks' : 'You have no recent trades'}
              </p>
            </div>
          )}
        </div>
      )}

      {!isLoading && history.length > 0 && (
        <div className="text-xs text-gray-600 text-center pt-3 border-t border-border">
          Showing last {history.length} trades from recent blocks.
          Events are fetched from Base Sepolia testnet.
        </div>
      )}
    </div>
  );
};

export default TradeHistory;
