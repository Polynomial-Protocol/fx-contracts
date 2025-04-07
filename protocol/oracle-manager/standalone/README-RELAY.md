# Binance Funding Rate Relay Service

A live demo service for your hackathon presentation that continuously fetches, signs, and displays Binance funding rates through an interactive web dashboard.

## Overview

This service:
1. Fetches real-time funding rates from Binance every 60 seconds
2. Signs the data with your private key
3. Provides a beautiful web dashboard to visualize the data
4. Makes the signed data available for your smart contracts

Perfect for demonstrating your TrustedSignerNode oracle system without having to manually run commands during your presentation.

## Quick Start

### Installation

1. Install the required dependencies:

```bash
cd fx-contracts/protocol/oracle-manager/standalone
npm install
```

### Running the Service

Start the relay service with:

```bash
# Format: npm run relay -- <SYMBOL> <PRIVATE_KEY> [PORT]
npm run relay -- BTCUSDT 0xYourPrivateKeyHere 3000
```

Parameters:
- `SYMBOL`: The trading pair to monitor (e.g., BTCUSDT, ETHUSDT)
- `PRIVATE_KEY`: Your Ethereum private key for signing (keep this secure!)
- `PORT`: (Optional) The port to run the web server on (default: 3000)

### Accessing the Dashboard

Once running, access the dashboard at:
```
http://localhost:3000
```

## Dashboard Features

![Dashboard Preview](https://i.imgur.com/example-image.png)

The dashboard provides:

- **Real-time funding rates**: Shows the current funding rate with color coding
- **Signer details**: Displays your signer address and current timestamp
- **Oracle data**: Shows the hex-encoded signed data and node parameters
- **Historical data**: Tracks recent funding rate changes

The data automatically refreshes every 60 seconds, or you can manually refresh with the button.

## During Your Demo

1. **Start the service** before your presentation begins
2. **Show the dashboard** to demonstrate real-time funding rates being signed
3. **Copy the node parameters** directly from the dashboard
4. **Paste into your smart contract interaction** to demonstrate on-chain verification

## Integration with Smart Contracts

### 1. Direct integration in your dApp

```javascript
// In your frontend code
async function getFundingRateData() {
  const response = await fetch('http://localhost:3000/api/latest');
  const data = await response.json();
  return data.nodeParameters; // This is what you send to your contract
}
```

### 2. Using with your smart contract

```solidity
// In your contract interaction
bytes memory parameters = 0x... // Copy from the dashboard
trustedSignerNode.process(new NodeOutput.Data[](0), parameters, new bytes32[](0), new bytes[](0));
```

## Customization

You can modify the `relay-service.js` file to:
- Change the update interval (default: 60 seconds)
- Add support for multiple trading pairs
- Customize the dashboard appearance
- Add transaction submission functionality

## Troubleshooting

Common issues:

1. **"Invalid private key"**: Ensure your private key is in the correct format (with or without 0x prefix)

2. **"Symbol not found"**: Verify the trading pair exists on Binance (e.g., BTCUSDT, ETHUSDT)

3. **"Connection refused"**: Make sure the port is available and not blocked by a firewall

4. **Slow updates**: Network latency to Binance API can affect response times 