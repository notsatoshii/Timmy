#!/bin/bash
# Setup foundry tools in PATH
export PATH="/home/lever/.foundry/bin:$PATH"

# Test if foundry tools are available
if ! command -v cast &> /dev/null; then
    echo "ERROR: cast not found in PATH. Run foundryup first."
    exit 1
fi

echo "Foundry tools are available in PATH"