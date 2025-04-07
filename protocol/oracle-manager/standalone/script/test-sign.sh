#!/bin/bash

# Generate a random private key for testing (without 0x prefix for forge)
PRIVATE_KEY=$(openssl rand -hex 32)
echo "Using test private key: 0x$PRIVATE_KEY"

# Set test environment variables
export ASSET_ID="ETH"
export PRICE="3500000000000000000000" # 3500 USD with 18 decimals
export TIMESTAMP=$(date +%s) # Current timestamp

# Set the private key as environment variable for Foundry
export FOUNDRY_PRIVATE_KEY="0x$PRIVATE_KEY"

# Run the signing script
echo "Running SignPrice script..."
forge script script/SignPrice.s.sol:SignPrice

echo "Script execution complete!" 