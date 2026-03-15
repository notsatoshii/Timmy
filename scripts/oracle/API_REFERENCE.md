# Polymarket API Reference
## Gamma API (Market Data) — No auth needed
- Base: https://gamma-api.polymarket.com
- Markets: GET /markets?closed=false&limit=100
- Single: GET /markets/{condition_id}
## CLOB API (Prices)
- Base: https://clob.polymarket.com
- Price: GET /midpoint?token_id={token_id}
- Book: GET /book?token_id={token_id}
## Websocket
- wss://ws-subscriptions-clob.polymarket.com/ws/market
- Subscribe: {"type":"market","assets_id":"TOKEN_ID"}
## Flow: polymarket_ref -> on-chain price
1. Resolve slug to token_id via Gamma API
2. Poll CLOB midpoint every 30s
3. Push to OracleAdapter.pushPrice() as 18-decimal WAD (0.88 = 880000000000000000)
## Rate Limits: ~100 req/min public, no auth for read-only
