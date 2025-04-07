#!/usr/bin/env node

/**
 * Demo Transaction Script
 * 
 * This script simulates a transaction with the TrustedSignerNode contract
 * by fetching the latest signed data from the relay service.
 * 
 * Usage:
 *   node demo-transaction.js <relay_url> <contract_address> <private_key>
 * 
 * Example:
 *   node demo-transaction.js http://localhost:3000 0x1234...5678 0xabcd...efgh
 */

const { ethers } = require('ethers');
const axios = require('axios');

// TrustedSignerNode contract ABI (simplified to just what we need)
const abi = [
  "function process(tuple(int256 price, uint256 timestamp)[] memory parentNodeOutputs, bytes memory parameters, bytes32[] memory runtimeKeys, bytes[] memory runtimeValues) public returns (tuple(int256 price, uint256 timestamp))"
];

async function main() {
  try {
    // Parse command line arguments
    const args = process.argv.slice(2);
    if (args.length < 3) {
      console.error('Usage: node demo-transaction.js <relay_url> <contract_address> <private_key>');
      process.exit(1);
    }

    const relayUrl = args[0];
    const contractAddress = args[1];
    const privateKey = args[2];
    
    console.log('=== Trusted Signer Oracle Demo Transaction ===');
    
    // Fetch the latest data from the relay service
    console.log(`\nFetching latest signed data from ${relayUrl}...`);
    const response = await axios.get(`${relayUrl}/api/latest`);
    const { symbol, fundingRate, timestamp, nodeParameters } = response.data;
    
    console.log(`\nReceived data for: ${symbol}`);
    console.log(`Funding Rate: ${fundingRate * 100}%`);
    console.log(`Timestamp: ${new Date(timestamp * 1000).toLocaleString()}`);
    
    // Setup wallet and provider
    // This is just for demonstration - in a real scenario you'd connect to your network
    console.log('\nPreparing transaction (simulation only)...');
    const provider = new ethers.JsonRpcProvider('http://localhost:8545'); // Assumes local node
    const wallet = new ethers.Wallet(privateKey, provider);
    
    // Get contract instance
    const contract = new ethers.Contract(contractAddress, abi, wallet);
    
    // Simulate process call
    console.log('\nSimulating transaction...');
    
    // In a real transaction, you would do:
    // const tx = await contract.process([], nodeParameters, [], []);
    // await tx.wait();
    
    // Instead, we'll just show what would be sent
    console.log('\nTransaction would send:');
    console.log(`To: ${contractAddress}`);
    console.log(`Function: process()`);
    console.log(`Parameters: ${nodeParameters.substring(0, 66)}...`);
    
    console.log('\nExpected result:');
    console.log(`Funding Rate: ${fundingRate * 100}%`);
    console.log(`Timestamp: ${new Date(timestamp * 1000).toLocaleString()}`);
    
    console.log('\n=== Demo Transaction Complete ===');
    console.log('Note: This was a simulation only. No actual transaction was sent.');
    console.log('In a real implementation, you would connect to your blockchain network');
    console.log('and submit this transaction to your deployed TrustedSignerNode contract.');
    
  } catch (error) {
    console.error('Error:', error.message || error);
    process.exit(1);
  }
}

// Run the script
main().catch(console.error); 