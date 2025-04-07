# Trusted Signer Oracle

A proof-of-concept implementation of a trusted signer oracle for Oracle Manager that enables fast listing of new assets.

## Overview

This oracle implementation allows trusted signers to provide price data for any asset, enabling rapid listing of new markets without waiting for those assets to be listed on CEXs or other price oracles.

The system consists of:

1. **TrustedSignerRegistry** - Manages the list of authorized signers
2. **TrustedSignerNode** - Implements the IExternalNode interface for Oracle Manager
3. **PriceDataSigner** - Helper contract for testing/demonstrating signature creation

## How It Works

1. Trusted entities (e.g., team members, partners) sign price data off-chain
2. The signature and price data are submitted to the oracle
3. The TrustedSignerNode verifies that:
   - The signature is valid
   - The signer is authorized in the TrustedSignerRegistry
   - The data is not stale (within the freshness threshold)
4. If all checks pass, the price data is returned to Oracle Manager

## Security Considerations

This is a proof-of-concept and prioritizes speed over decentralization. In a production environment, consider:

- Using multiple signers with a minimum threshold (e.g., 3-of-5 signatures required)
- Implementing circuit breakers to prevent extreme price moves
- Combining with other price sources using ReducerNode (e.g., median of multiple sources)
- Adding regular audits and monitoring of signer activity
- Implementing an on-chain governance mechanism for signer management

## Integration with Oracle Manager

To use the trusted signer oracle:

1. Deploy the TrustedSignerRegistry contract
2. Add authorized signers to the registry
3. Deploy the TrustedSignerNode contract with the registry address
4. Register the node with Oracle Manager using the ExternalNode type (2)
5. Have authorized signers provide signed price data for assets
6. Use the node ID in your contracts to get price data

## Usage Example

```solidity
// Register the TrustedSignerNode with Oracle Manager
bytes32 nodeId = oracleManager.registerNode(
    NodeDefinition.NodeType.EXTERNAL, // 2
    abi.encode(
        trustedSignerNodeAddress,
        "NEW_TOKEN",
        signedPriceData
    ),
    [] // No parent nodes
);

// Get the price data
NodeOutput.Data memory priceData = oracleManager.process(nodeId);
```

## Off-chain Signing

The `sign-price-data.js` script demonstrates how to sign price data off-chain. In a production environment, this would be handled by a secure signing service.

## Future Improvements

1. Multi-signature support
2. Integration with ZK-TLS for automated price fetching from APIs
3. Time-weighted average price (TWAP) support
4. Volatility and liquidity metrics
5. On-chain governance for signer management 