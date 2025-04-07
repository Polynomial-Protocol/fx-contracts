# Trusted Signer Oracle Deployment Guide

This guide explains how to deploy and use the Trusted Signer Oracle on Polynomial Sepolia.

## Prerequisites

1. Node.js and npm installed
2. ETH on Polynomial Sepolia for deployment and transactions
3. Access to the Oracle Manager contract address

## Setup

1. **Install dependencies**:
   ```bash
   cd fx-contracts/protocol/oracle-manager
   npm install dotenv axios ethers@5.7.2 @types/node typescript ts-node
   ```

2. **Create a .env file**:
   ```bash
   cp .env.template .env
   ```

3. **Edit the .env file** with your configuration:
   - Add your deployment private key (`DEPLOYER_PRIVATE_KEY`)
   - Add your signer private key (`SIGNER_PRIVATE_KEY`)
   - Verify RPC URL is correct (`RPC_URL`)
   - Add Oracle Manager address (`ORACLE_MANAGER_ADDRESS`)

## Deployment Process

1. **Compile the contracts**:
   ```bash
   npx hardhat compile
   ```

2. **Deploy the contracts**:
   ```bash
   # Compile TypeScript
   npx tsc scripts/deploy-trusted-signer.ts

   # Run deployment
   node scripts/deploy-trusted-signer.js
   ```
   
   This will:
   - Deploy TrustedSignerRegistry
   - Authorize your signer address
   - Deploy TrustedSignerNode
   - Save deployment info to deployment-info.json
   - Print the addresses to add to your .env file

3. **Update your .env file** with the deployed contract addresses:
   ```
   TRUSTED_SIGNER_REGISTRY_ADDRESS=<address from previous step>
   TRUSTED_SIGNER_NODE_ADDRESS=<address from previous step>
   ```

## Using the Oracle

### For Asset Prices

1. **Generate signed price data**:
   ```bash
   # Create a price signing script (example for ETH at $3500)
   node -e "
   const { ethers } = require('ethers');
   const wallet = new ethers.Wallet('YOUR_SIGNER_PRIVATE_KEY');
   const assetId = 'ETH';
   const price = ethers.utils.parseUnits('3500', 18);
   const timestamp = Math.floor(Date.now() / 1000);
   const messageHash = ethers.utils.solidityKeccak256(
     ['string', 'int256', 'uint256'], 
     [assetId, price, timestamp]
   );
   wallet.signMessage(ethers.utils.arrayify(messageHash)).then(signature => {
     const encodedData = ethers.utils.defaultAbiCoder.encode(
       ['int256', 'uint256'], [price, timestamp]
     );
     console.log({
       assetId,
       price: price.toString(),
       timestamp,
       signature: ethers.utils.hexConcat([encodedData, signature])
     });
   });
   "
   ```

2. **Register with Oracle Manager**:
   ```bash
   # Compile TypeScript
   npx tsc scripts/register-node.ts

   # Run registration (customize parameters)
   ASSET_ID=ETH SIGNATURE=<from previous step> node scripts/register-node.js
   ```

### For Binance Funding Rates

1. **Run the funding rate signer**:
   ```bash
   # Compile TypeScript
   npx tsc scripts/binance-funding-rate-signer.ts

   # Run the signer
   node scripts/binance-funding-rate-signer.js
   ```

2. **Register with Oracle Manager**:
   ```bash
   # Compile TypeScript
   npx tsc scripts/register-funding-rate-node.ts

   # Run registration
   node scripts/register-funding-rate-node.js
   ```

## Automating Price Updates

For production environments, you should set up an automated system to regularly update prices:

1. **Set up a cronjob or service**:
   ```bash
   # Install PM2 for service management
   npm install -g pm2

   # Create ecosystem.config.js
   echo "module.exports = {
     apps: [{
       name: 'price-signer',
       script: 'scripts/binance-funding-rate-signer.js',
       autorestart: true,
       watch: false,
       env: {
         NODE_ENV: 'production'
       }
     }]
   }" > ecosystem.config.js

   # Start the service
   pm2 start ecosystem.config.js
   ```

2. **Make it start on system boot**:
   ```bash
   pm2 startup
   pm2 save
   ```

## Troubleshooting

- **Gas errors**: Adjust gas settings in the .env file
- **RPC errors**: Verify Polynomial Sepolia RPC URL and status
- **Freshness errors**: Ensure the signed price timestamp is recent
- **Oracle Manager errors**: Verify Oracle Manager address and parameters

## Security Considerations

- Store private keys securely
- Run the price signer service on secure infrastructure
- Monitor the service for uptime
- Consider implementing multiple signers for redundancy 