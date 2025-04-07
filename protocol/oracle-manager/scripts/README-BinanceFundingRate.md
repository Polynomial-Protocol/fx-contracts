# Binance BTC Funding Rate Oracle

This directory contains scripts for fetching BTC funding rates from Binance, signing them with a trusted signer, and registering them with the Oracle Manager.

## Overview

These scripts enable the Polynomial protocol to create markets based on Binance BTC funding rates using the trusted signer oracle implementation.

## Scripts

1. **binance-funding-rate-signer.ts** - Fetches the latest BTC funding rate from Binance, signs it, and saves the signed data to a file.
2. **register-funding-rate-node.ts** - Registers the signed funding rate data with Oracle Manager.

## Setup

1. Install dependencies:
   ```bash
   npm install dotenv axios ethers@5.7.2 @types/node
   ```

2. Create a `.env` file with the following variables:
   ```
   PRIVATE_KEY=your_private_key_here
   ORACLE_MANAGER_ADDRESS=oracle_manager_contract_address
   TRUSTED_SIGNER_NODE_ADDRESS=trusted_signer_node_contract_address
   RPC_URL=https://rpc.sepolia.polynomial.fi
   ```

## Usage

### 1. Fetch and Sign Funding Rate

```bash
# Compile TypeScript files
npx tsc binance-funding-rate-signer.ts

# Run the script
node binance-funding-rate-signer.js
```

This will:
- Fetch the latest BTC funding rate from Binance
- Sign it using your private key
- Save the signature to `btc-funding-rate-signature.json`
- Display the signature information

### 2. Register with Oracle Manager

```bash
# Compile TypeScript files
npx tsc register-funding-rate-node.ts

# Run the script
node register-funding-rate-node.js
```

This will:
- Read the signature from `btc-funding-rate-signature.json`
- Connect to Oracle Manager
- Register a new external node with the BTC funding rate data
- Save the node ID to `btc-funding-rate-node.json`

## Creating a Service

To run this as a service that regularly updates the funding rate:

1. Install PM2:
   ```bash
   npm install -g pm2
   ```

2. Create a `ecosystem.config.js` file:
   ```javascript
   module.exports = {
     apps: [
       {
         name: "btc-funding-rate-signer",
         script: "binance-funding-rate-signer.js",
         autorestart: true,
         watch: false,
         max_memory_restart: "1G",
       }
     ]
   };
   ```

3. Start the service:
   ```bash
   pm2 start ecosystem.config.js
   ```

4. To make it run on system startup:
   ```bash
   pm2 startup
   pm2 save
   ```

## Technical Details

### Funding Rate Format

The funding rate is a percentage value (e.g., 0.01% or -0.02%) that is converted to an 18-decimal fixed-point number for use in the oracle system. This allows proper representation of both positive and negative rates.

### Freshness

The script fetches the latest funding rate. The trusted signer node enforces a freshness constraint of 5 minutes, ensuring that the oracle data is relatively current.

### Security Considerations

For production use:
- Store private keys securely, not in code
- Run the signer service on secure infrastructure
- Consider implementing multiple signers for redundancy
- Monitor the service for uptime and accuracy 