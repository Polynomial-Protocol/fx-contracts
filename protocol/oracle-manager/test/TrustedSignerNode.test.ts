import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("TrustedSignerNode", function () {
  let trustedSignerRegistry: Contract;
  let trustedSignerNode: Contract;
  let priceDataSigner: Contract;
  let owner: Signer;
  let signer1: Signer;
  let signer2: Signer;
  let randomUser: Signer;
  
  // Test asset
  const assetId = "ETH";

  beforeEach(async function () {
    [owner, signer1, signer2, randomUser] = await ethers.getSigners();

    // Deploy TrustedSignerRegistry
    const TrustedSignerRegistry = await ethers.getContractFactory("TrustedSignerRegistry");
    trustedSignerRegistry = await TrustedSignerRegistry.deploy();
    await trustedSignerRegistry.deployed();

    // Deploy TrustedSignerNode
    const TrustedSignerNode = await ethers.getContractFactory("TrustedSignerNode");
    trustedSignerNode = await TrustedSignerNode.deploy(trustedSignerRegistry.address);
    await trustedSignerNode.deployed();

    // Deploy PriceDataSigner (helper for testing)
    const PriceDataSigner = await ethers.getContractFactory("PriceDataSigner");
    priceDataSigner = await PriceDataSigner.deploy();
    await priceDataSigner.deployed();

    // Add signer1 as authorized signer
    await trustedSignerRegistry.authorizeSigner(await signer1.getAddress());
  });

  it("should support the IExternalNode interface", async function () {
    const IExternalNodeId = "0x3c508a742eed8c95efefc9f6f24b3a3c5864df5a16ca1e2f12d59a4c1574323d"; // IExternalNode interface ID
    expect(await trustedSignerNode.supportsInterface(IExternalNodeId)).to.be.true;
  });

  it("should allow registry owner to authorize and revoke signers", async function () {
    const signer2Address = await signer2.getAddress();
    
    // Initially not authorized
    expect(await trustedSignerRegistry.isAuthorizedSigner(signer2Address)).to.be.false;
    
    // Authorize signer2
    await trustedSignerRegistry.authorizeSigner(signer2Address);
    expect(await trustedSignerRegistry.isAuthorizedSigner(signer2Address)).to.be.true;
    
    // Revoke signer2
    await trustedSignerRegistry.revokeSigner(signer2Address);
    expect(await trustedSignerRegistry.isAuthorizedSigner(signer2Address)).to.be.false;
  });

  it("should validate node parameters", async function () {
    // Create valid parameters
    const validParams = ethers.utils.defaultAbiCoder.encode(
      ["string", "bytes"], 
      [assetId, "0x1234567890"]
    );
    
    // Create invalid parameters (too short)
    const invalidParams = "0x1234";
    
    // Check validation
    expect(await trustedSignerNode.validateParameters(validParams)).to.be.true;
    await expect(trustedSignerNode.validateParameters(invalidParams)).to.be.reverted;
  });

  it("should retrieve price from an authorized signer", async function () {
    // Mock data - in a real environment this would be signed off-chain
    const mockPrice = ethers.utils.parseEther("1500"); // 1500 USD with 18 decimals
    const mockTimestamp = Math.floor(Date.now() / 1000); // Current timestamp
    
    // Create a mock signature - this is just for testing
    // In a real implementation, you would sign this off-chain with a private key
    const mockSignature = ethers.utils.defaultAbiCoder.encode(
      ["int256", "uint256", "bytes"], 
      [mockPrice, mockTimestamp, "0x1234567890"]
    );
    
    // Create parameters for the node
    const params = ethers.utils.defaultAbiCoder.encode(
      ["string", "bytes"], 
      [assetId, mockSignature]
    );
    
    // Define mock node definition
    const nodeDefinition = {
      parents: [],
      nodeType: 2, // ExternalNode type
      parameters: ethers.utils.defaultAbiCoder.encode(
        ["address", "string", "bytes"],
        [trustedSignerNode.address, assetId, mockSignature]
      )
    };
    
    // Validate the node definition
    expect(await trustedSignerNode.isValid(nodeDefinition)).to.be.true;
    
    // TODO: Once the signature logic is properly implemented, add test for processing
    // the node with a real signature
  });
}); 