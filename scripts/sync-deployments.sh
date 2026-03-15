#!/bin/bash
# Syncs deployment JSON files from project root to frontend public directory.
# Run after any new deployment to update frontend contract addresses.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DEST_DIR="$ROOT_DIR/frontend/user-app/public/deployments"

mkdir -p "$DEST_DIR"

SYNCED=0
for f in core-deployment.json pool-deployment.json engines-deployment.json; do
  if [ -f "$ROOT_DIR/$f" ]; then
    cp "$ROOT_DIR/$f" "$DEST_DIR/$f"
    echo "Synced $f"
    SYNCED=$((SYNCED + 1))
  else
    echo "WARN: $ROOT_DIR/$f not found"
  fi
done

echo "Done. $SYNCED deployment file(s) synced to $DEST_DIR"
