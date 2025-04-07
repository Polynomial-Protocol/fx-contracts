.PHONY: install test deploy-trusted-signer register-node sign-price clean

# Initialize with environment variables
include .env
export

# Install dependencies
install:
	forge install

# Run tests
test:
	forge test -vvv

# Run specific test
test-trusted-signer:
	forge test --match-contract TrustedSignerNodeTest -vvv

# Deploy trusted signer oracle
deploy-trusted-signer:
	forge script script/foundry/DeployTrustedSigner.s.sol:DeployTrustedSigner --rpc-url $(POLYNOMIAL_SEPOLIA_RPC_URL) --private-key $(DEPLOYER_PRIVATE_KEY) --broadcast --verify

# Register node in Oracle Manager
register-node:
	forge script script/foundry/RegisterNode.s.sol:RegisterNode --rpc-url $(POLYNOMIAL_SEPOLIA_RPC_URL) --private-key $(DEPLOYER_PRIVATE_KEY) --broadcast

# Generate signed price data
sign-price:
	forge script script/foundry/SignPrice.s.sol:SignPrice --rpc-url $(POLYNOMIAL_SEPOLIA_RPC_URL)

# Clean build artifacts
clean:
	forge clean

# Help command
help:
	@echo "Available targets:"
	@echo "  install              - Install dependencies"
	@echo "  test                 - Run all tests"
	@echo "  test-trusted-signer  - Run only TrustedSignerNode tests"
	@echo "  deploy-trusted-signer- Deploy the TrustedSignerRegistry and TrustedSignerNode contracts"
	@echo "  register-node        - Register the TrustedSignerNode with OracleManager"
	@echo "  sign-price           - Generate signed price data for testing/integration"
	@echo "  clean                - Clean build artifacts"
	@echo ""
	@echo "Environment setup:"
	@echo "  Create a .env file from .env.example and fill in required values"