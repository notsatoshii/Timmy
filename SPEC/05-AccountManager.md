# SPEC: AccountManager

## Purpose
User collateral accounts. Deposits USDT, tracks free vs locked collateral, credits/debits PnL. Thin contract — no business logic beyond accounting.

## Dependencies
- USDT token (ERC-20, external)

## Build Priority
Phase 1 — Foundation. ExecutionEngine calls lockCollateral/releaseCollateral. LeverVault shares the same USDT pool conceptually but is separate.

## Access Control
- Any user: deposit, withdraw
- EXECUTION_ENGINE role: lockCollateral, releaseCollateral, creditPnL, debitPnL
- LIQUIDATION_ENGINE role: releaseCollateral, creditPnL, debitPnL
- SETTLEMENT_ENGINE role: releaseCollateral, creditPnL, debitPnL

## State Variables
```solidity
mapping(address => uint256) private _balances;       // Total deposited
mapping(address => uint256) private _lockedCollateral; // Locked in positions
IERC20 public immutable usdt;
```

## Key Functions

### deposit(uint256 amount)
- Transfer USDT from caller to contract
- Increase _balances[caller] by amount
- Emit CollateralDeposited

### withdraw(uint256 amount)
- Require: getFreeCollateral(caller) >= amount
- Transfer USDT from contract to caller
- Decrease _balances[caller] by amount
- Emit CollateralWithdrawn

### lockCollateral(address user, uint256 amount)
- Require: getFreeCollateral(user) >= amount
- Increase _lockedCollateral[user] by amount
- Called when a position opens

### releaseCollateral(address user, uint256 amount)
- Decrease _lockedCollateral[user] by amount
- Called when a position closes

### creditPnL(address user, uint256 amount)
- Increase _balances[user] by amount
- Used for profitable position closes

### debitPnL(address user, uint256 amount)
- Decrease _balances[user] by min(amount, _balances[user])
- Used for losing position closes. Cannot go negative.

### getFreeCollateral(address user) → uint256
```
return _balances[user] - _lockedCollateral[user]
```

## Edge Cases
- Withdraw more than free collateral → revert
- debitPnL more than balance → debit what's available, loss is bad debt handled elsewhere
- User with no deposit calls withdraw → revert
- deposit(0) → revert (zero amount)
- Reentrancy: use ReentrancyGuard on deposit/withdraw (USDT transfer could be malicious token in testing)

