#!/bin/bash
source /home/lever/lever-protocol/control-plane/deploy-env.sh
BORROW_ENGINE=0x706578de003912C71e534949d8b8DDd5108950e1
FUNDING_ENGINE=0x1C538eFA480C85D032c0ad45Dd87f9876c16Cbbe
while true; do
  cast send $BORROW_ENGINE "accrueAll()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL 2>/dev/null
  for MKT in 0x2841ef32b61fb3472aadbfc70d787a1bfaf5d0218c9601b87963af7bcca1bcf1 0x9fe694e72b00a6aab573e11a17e2240b64d7aca455305b65289b77cc2f2d077a 0x62fcede467dc87c6e1001987c73f5b90ddae5df334e990414a89b6e48cf1826d 0xe824af6184169f8f70511158f848d86056ebcc5b283928333c722159bafd82e2; do
    cast send $FUNDING_ENGINE "accrueFunding(bytes32)" "$MKT" --private-key $PRIVATE_KEY --rpc-url $RPC_URL 2>/dev/null
  done
  sleep 60
done
