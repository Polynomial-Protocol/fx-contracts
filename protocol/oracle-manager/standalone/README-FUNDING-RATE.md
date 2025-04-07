# Binance Funding Rate Oracle

This module fetches and signs Binance funding rate data for use with the TrustedSignerNode oracle. It provides real-time funding rate data from Binance's perpetual futures market.

## Overview

Funding rates are periodic payments exchanged between long and short positions in perpetual futures contracts. This oracle fetches the latest funding rate from Binance, signs it with your private key, and formats it for use with our TrustedSignerNode contract.

## Installation

1. Install Node.js dependencies:

```bash
cd fx-contracts/protocol/oracle-manager/standalone
npm install
```

## Usage

### Fetching and Signing Funding Rates

Run the script with a trading pair symbol and your private key:

```bash
# Format: npm run fetch-rate -- <SYMBOL> <PRIVATE_KEY>
npm run fetch-rate -- BTCUSDT 0x123...your_private_key_here
```

Example output:

```
Signer address: 0x1234...5678
Fetching funding rate for BTCUSDT...
Symbol: BTCUSDT
Funding Rate: 0.0001 (100000000000000)
Timestamp: 1681234567
Next Funding Time: 2023-04-11T12:00:00.000Z

--- RESULTS ---
Signed Data (hex): 0x00000000000000000000000000000000000000000000000000000000000186a000000000000000000000000000000000000000000000000000000006436f4778efcddf01223...
Node Parameters (hex): 0x000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000...
```

### Integrating with Smart Contracts

1. Deploy the TrustedSignerRegistry and TrustedSignerNode contracts:

```bash
forge script script/DeployTrustedSignerOracle.s.sol:DeployTrustedSignerOracle --broadcast --rpc-url <RPC_URL>
```

2. Authorize your signer address in the registry:

```solidity
// Call this function on the deployed registry
registry.authorizeSigner(0x1234...yourSignerAddress);
```

3. Use the signed data to update funding rates on-chain:

```solidity
// The node parameters from the script output can be directly used here
bytes memory parameters = 0x00000000...;
node.process(new NodeOutput.Data[](0), parameters, new bytes32[](0), new bytes[](0));
```

## Technical Details

### Supported Trading Pairs

The script supports all perpetual futures trading pairs available on Binance, including but not limited to:
- BTCUSDT
- ETHUSDT
- SOLUSDT
- BNBUSDT

### Data Format

The funding rate is fetched from Binance's Premium Index API and scaled to 18 decimals for blockchain compatibility:

```
Actual Funding Rate: 0.0001 (0.01%)
Scaled Value: 0.0001 * 10^18 = 100000000000000
```

### Security Considerations

- Private keys should never be exposed or checked into source control
- For production use, consider using environment variables or secure key management solutions
- Only authorized signers in the TrustedSignerRegistry can submit valid price updates

## Automation

For production use, you should set up this script to run automatically at regular intervals:

### Sample Cron Job (runs every hour)

```bash
0 * * * * cd /path/to/project && npm run fetch-rate -- BTCUSDT $PRIVATE_KEY > /var/log/funding-rate-oracle.log 2>&1
```

### Running as a Service

Create a systemd service for reliable execution:

```ini
[Unit]
Description=Binance Funding Rate Oracle Service
After=network.target

[Service]
Type=simple
User=oracle
WorkingDirectory=/path/to/project
ExecStart=/usr/bin/npm run fetch-rate -- BTCUSDT $PRIVATE_KEY
Restart=always
Environment="PRIVATE_KEY=your_private_key_here"

[Install]
WantedBy=multi-user.target
```

## Troubleshooting

Common issues:

1. **API Rate Limiting**: Binance limits API requests. If you hit rate limits, add delay between requests.

2. **Invalid Signature**: Ensure the signer address is authorized in the TrustedSignerRegistry contract.

3. **Outdated Funding Rate**: The TrustedSignerNode rejects data older than 5 minutes. Ensure your server's clock is synchronized. 