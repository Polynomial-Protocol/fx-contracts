# Trusted Signer Oracle - Foundry Implementation

This guide covers setting up and deploying the Trusted Signer Oracle using Foundry, which is much faster than Hardhat.

## Setup Foundry

First, install Foundry if you haven't already:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Initialize Foundry in the project

Initialize Foundry in the existing project:

```bash
cd fx-contracts/protocol/oracle-manager
forge init --no-commit
```

This adds the necessary Foundry files without overwriting your existing code.

## Update Dependencies

Add Forge-std for testing and scripting:

```bash
forge install foundry-rs/forge-std
```

## Run the Deployment Script

1. Create a `.env` file:

```
PRIVATE_KEY=your_private_key_here
RPC_URL=https://rpc.sepolia.polynomial.fi
ORACLE_MANAGER_ADDRESS=oracle_manager_address_here
```

2. Deploy the contracts:

```bash
# Load environment variables
source .env

# Deploy the Trusted Signer Oracle system
forge script script/DeployTrustedSignerOracle.s.sol:DeployTrustedSignerOracle \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

This will deploy both the TrustedSignerRegistry and TrustedSignerNode contracts, and authorize your address as a signer.

## Generate Signed Price Data

You can use the PriceDataSigner to generate signed price data with Foundry:

```bash
# Create a temporary file with the signing script
cat > script/SignPrice.s.sol << 'EOL'
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Script.sol";

contract SignPrice is Script {
    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        string memory assetId = vm.envString("ASSET_ID");
        int256 price = int256(vm.envUint("PRICE"));
        uint256 timestamp = block.timestamp;
        
        // Log the data that will be signed
        console.log("Signing price data for asset:", assetId);
        console.log("Price:", uint256(price));
        console.log("Timestamp:", timestamp);
        
        // Create the message hash
        bytes32 messageHash = keccak256(abi.encodePacked(assetId, price, timestamp));
        
        // Sign the message hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Encode the price data
        bytes memory encodedData = abi.encode(price, timestamp);
        
        // Combine into the complete signature
        bytes memory completeSignature = bytes.concat(encodedData, signature);
        
        // Output the signature details
        console.log("Complete signature:");
        console.logBytes(completeSignature);
        
        // Write to a file for later use
        string memory filePath = string.concat("signature-", assetId, ".txt");
        vm.writeFile(filePath, vm.toString(completeSignature));
        console.log("Signature written to:", filePath);
    }
}
EOL

# Set the asset and price (3500 USD for ETH)
export ASSET_ID=ETH
export PRICE=3500000000000000000000

# Generate the signature
forge script script/SignPrice.s.sol:SignPrice --private-key $PRIVATE_KEY
```

## Register with Oracle Manager

Create a script to register the node with Oracle Manager:

```bash
cat > script/RegisterNode.s.sol << 'EOL'
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Script.sol";

interface IOracleManager {
    function registerNode(uint256 nodeType, bytes memory parameters, bytes32[] memory parents) external returns (bytes32 nodeId);
    function getNodeId(uint256 nodeType, bytes memory parameters, bytes32[] memory parents) external view returns (bytes32 nodeId);
    function process(bytes32 nodeId) external view returns (
        int256 price, 
        uint256 timestamp, 
        uint256 unused1, 
        uint256 unused2
    );
}

contract RegisterNode is Script {
    function run() public {
        // Get configuration from environment
        address oracleManager = vm.envAddress("ORACLE_MANAGER_ADDRESS");
        address trustedSignerNode = vm.envAddress("TRUSTED_SIGNER_NODE_ADDRESS");
        string memory assetId = vm.envString("ASSET_ID");
        string memory signatureFile = vm.envString("SIGNATURE_FILE");
        
        // Read the signature from file
        string memory signatureHex = vm.readFile(signatureFile);
        bytes memory signature = vm.parseBytes(signatureHex);
        
        console.log("Registering node for asset:", assetId);
        console.log("Oracle Manager:", oracleManager);
        console.log("Trusted Signer Node:", trustedSignerNode);
        
        // Encode the parameters for the external node
        bytes memory parameters = abi.encode(trustedSignerNode, assetId, signature);
        
        vm.startBroadcast();
        
        // Register the node with Oracle Manager (NodeType.EXTERNAL = 2)
        bytes32 nodeId = IOracleManager(oracleManager).registerNode(2, parameters, new bytes32[](0));
        
        vm.stopBroadcast();
        
        console.log("Node registered with ID:", vm.toString(nodeId));
        
        // Process the node to verify it works
        try IOracleManager(oracleManager).process(nodeId) returns (
            int256 price, 
            uint256 timestamp,
            uint256,
            uint256
        ) {
            console.log("Node processed successfully!");
            console.log("Price:", uint256(price));
            console.log("Timestamp:", timestamp);
        } catch Error(string memory reason) {
            console.log("Failed to process node:", reason);
        } catch {
            console.log("Failed to process node (unknown error)");
        }
    }
}
EOL

# Register the node
export TRUSTED_SIGNER_NODE_ADDRESS=<address from deployment>
export SIGNATURE_FILE=signature-ETH.txt

forge script script/RegisterNode.s.sol:RegisterNode \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Testing with Foundry

You can also create unit tests:

```bash
mkdir -p test/external-nodes

cat > test/external-nodes/TrustedSignerNode.t.sol << 'EOL'
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "forge-std/Test.sol";
import "../../contracts/nodes/external-nodes/TrustedSignerRegistry.sol";
import "../../contracts/nodes/external-nodes/TrustedSignerNode.sol";
import "../../contracts/storage/NodeOutput.sol";
import "../../contracts/storage/NodeDefinition.sol";

contract TrustedSignerNodeTest is Test {
    TrustedSignerRegistry public registry;
    TrustedSignerNode public node;
    address signer = address(0x1);
    
    function setUp() public {
        // Deploy the registry and node
        registry = new TrustedSignerRegistry();
        node = new TrustedSignerNode(address(registry));
        
        // Authorize the signer
        registry.authorizeSigner(signer);
    }
    
    function testNodeSupportsInterface() public {
        // IExternalNode interface ID
        bytes4 externalNodeInterfaceId = 0x3c508a74;
        assertTrue(node.supportsInterface(externalNodeInterfaceId));
    }
    
    function testAuthorizeSigner() public {
        assertTrue(registry.isAuthorizedSigner(signer));
        
        // Test revoking
        registry.revokeSigner(signer);
        assertFalse(registry.isAuthorizedSigner(signer));
    }
    
    function testParameterValidation() public {
        // Valid parameters
        bytes memory validParams = abi.encode("ETH", hex"1234567890");
        assertTrue(node.validateParameters(validParams));
        
        // Invalid parameters (too short)
        bytes memory invalidParams = hex"1234";
        vm.expectRevert();
        node.validateParameters(invalidParams);
    }
    
    // Additional tests for signature verification, processing, etc.
}
EOL
```

Run the tests with:

```bash
forge test
```

## Advantages of Foundry

- Much faster compilation and testing
- Simple command-line scripts
- Better gas reporting
- More powerful debugging tools

For more information, see the [Foundry Book](https://book.getfoundry.sh/). 