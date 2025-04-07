# Trusted Signer Oracle

A simple oracle solution that verifies price data signed by authorized signers.

## Overview

The Trusted Signer Oracle consists of two main components:

1. **TrustedSignerRegistry**: Manages the authorized signers who can provide price data
2. **TrustedSignerNode**: Processes signed price data and verifies its authenticity

This implementation is built with Foundry for faster compilation, testing, and deployment.

## Setup

### Prerequisites

- [Foundry](https://getfoundry.sh/) installed on your machine
- An Ethereum private key for signing and deployment

### Installation

Clone this repository and install dependencies:

```bash
git clone <repository-url>
cd <repository-directory>
forge install
```

## Usage

### Testing

Run the test suite:

```bash
forge test
```

For detailed test output:

```bash
forge test -vvv
```

To run a specific test:

```bash
forge test --match-contract TrustedSignerSigningTest -vvv
```

### Deployment

Deploy the Trusted Signer Oracle contracts:

```bash
# Create a .env file with your configuration
echo "PRIVATE_KEY=your_private_key_here" > .env
echo "SIGNER_ADDRESS=authorized_signer_address" >> .env

# Deploy the contracts
source .env
forge script script/DeployTrustedSignerOracle.s.sol:DeployTrustedSignerOracle --rpc-url <RPC_URL> --broadcast
```

If `SIGNER_ADDRESS` is not provided, the deployer address will be used as the authorized signer.

### Signing Price Data

Generate signed price data using the SignPrice script:

```bash
# Set environment variables for the price data
export ASSET_ID=ETH
export PRICE=3500000000000000000000  # 3500 USD with 18 decimals
export TIMESTAMP=$(date +%s)  # Current timestamp

# Run the signing script
forge script script/SignPrice.s.sol:SignPrice --private-key $PRIVATE_KEY
```

This will output the signature details and save the encoded signed data to a file named `signature-ETH.txt`.

### Registering with Oracle Manager

Register the TrustedSignerNode with the Oracle Manager:

```bash
# Set environment variables
export NODE_ADDRESS=<deployed_node_address>
export ORACLE_MANAGER_ADDRESS=<oracle_manager_address>
export NODE_ID="trusted-signer-eth-usd"
export ASSET_ID=ETH

# Run the registration script
forge script script/RegisterTrustedSignerNode.s.sol:RegisterTrustedSignerNode --rpc-url <RPC_URL> --broadcast
```

## Contract Details

### TrustedSignerRegistry

This contract manages the list of authorized signers who can provide price data.

Key functions:
- `authorizeSigner(address signer)`: Add a signer to the authorized list
- `revokeSigner(address signer)`: Remove a signer from the authorized list
- `isAuthorizedSigner(address signer)`: Check if a signer is authorized

### TrustedSignerNode

This contract processes and verifies signed price data.

Key functions:
- `process(NodeOutput.Data[] memory parentNodeOutputs, bytes memory parameters, bytes32[] memory runtimeKeys, bytes[] memory runtimeValues)`: Process signed price data
- `validateParameters(bytes memory parameters)`: Validate the node parameters

## Price Data Format

The signed price data consists of:
1. Price value (int256)
2. Timestamp (uint256)
3. Signature (bytes)

The message signed is a hash of:
- Asset ID (string)
- Price (int256)
- Timestamp (uint256)

## Security Considerations

- Only authorized signers can provide valid price data
- Price data with outdated timestamps is rejected
- Signatures are validated using EIP-191 standard signature verification

## Development

### Project Structure

```
.
├── contracts/
│   ├── interfaces/
│   │   └── external/
│   │       └── IExternalNode.sol
│   └── nodes/
│       └── external-nodes/
│           ├── TrustedSignerNode.sol
│           └── TrustedSignerRegistry.sol
├── script/
│   ├── DeployTrustedSignerOracle.s.sol
│   ├── RegisterTrustedSignerNode.s.sol
│   └── SignPrice.s.sol
└── test/
    ├── TrustedSignerTest.sol
    └── TrustedSignerSigningTest.sol
```

### Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request
