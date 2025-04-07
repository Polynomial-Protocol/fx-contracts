#!/usr/bin/env node

/**
 * Binance Funding Rate Data Fetcher and Signer
 * 
 * This script fetches the latest funding rate data from Binance,
 * signs it using the provided private key, and outputs it in a format
 * that can be used with the TrustedSignerNode contract.
 * 
 * Usage:
 *   node fetch-binance-funding-rate.js <symbol> <private_key>
 * 
 * Example:
 *   node fetch-binance-funding-rate.js BTCUSDT 0x123...456
 * 
 * The output will be a hex string that can be used as the signedData parameter
 * for the TrustedSignerNode contract.
 */

const { ethers } = require('ethers');
const axios = require('axios');

// Constants
const BINANCE_API_URL = 'https://fapi.binance.com/fapi/v1/premiumIndex';
const DECIMAL_MULTIPLIER = ethers.parseEther('1'); // 10^18

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: node fetch-binance-funding-rate.js <symbol> <private_key>');
    process.exit(1);
  }

  const symbol = args[0].toUpperCase();
  const privateKey = args[1];
  
  try {
    // Create a wallet from the private key
    const wallet = new ethers.Wallet(privateKey);
    console.log(`Signer address: ${wallet.address}`);
    
    // Fetch the funding rate from Binance
    console.log(`Fetching funding rate for ${symbol}...`);
    const fundingRate = await fetchFundingRate(symbol);
    
    // Convert funding rate to the expected format (multiplied by 10^18)
    const fundingRateScaled = ethers.parseEther(fundingRate.lastFundingRate.toString());
    
    // Get the current timestamp
    const timestamp = Math.floor(Date.now() / 1000);
    
    console.log(`Symbol: ${symbol}`);
    console.log(`Funding Rate: ${fundingRate.lastFundingRate} (${fundingRateScaled.toString()})`);
    console.log(`Timestamp: ${timestamp}`);
    console.log(`Next Funding Time: ${new Date(fundingRate.nextFundingTime).toISOString()}`);
    
    // Create and sign the message
    const signedData = await signFundingRate(wallet, symbol, fundingRateScaled, timestamp);
    
    // Generate the node parameters
    const nodeParameters = ethers.AbiCoder.defaultAbiCoder().encode(
      ['string', 'bytes'],
      [symbol, signedData]
    );
    
    console.log('\n--- RESULTS ---');
    console.log(`Signed Data (hex): ${signedData}`);
    console.log(`Node Parameters (hex): ${nodeParameters}`);
    console.log('\nTo use this data with TrustedSignerNode:');
    console.log(`1. Ensure the signer address (${wallet.address}) is authorized in the TrustedSignerRegistry`);
    console.log(`2. Call process() on TrustedSignerNode with the Node Parameters as the 'parameters' argument`);
    
  } catch (error) {
    console.error('Error:', error.message || error);
    process.exit(1);
  }
}

/**
 * Fetch the latest funding rate from Binance API
 */
async function fetchFundingRate(symbol) {
  try {
    const response = await axios.get(BINANCE_API_URL, {
      params: { symbol }
    });
    
    return {
      symbol: response.data.symbol,
      markPrice: parseFloat(response.data.markPrice),
      indexPrice: parseFloat(response.data.indexPrice),
      lastFundingRate: parseFloat(response.data.lastFundingRate),
      nextFundingTime: parseInt(response.data.nextFundingTime)
    };
  } catch (error) {
    if (error.response) {
      throw new Error(`Binance API error: ${error.response.data.msg || JSON.stringify(error.response.data)}`);
    }
    throw error;
  }
}

/**
 * Sign the funding rate data
 */
async function signFundingRate(wallet, symbol, fundingRateScaled, timestamp) {
  // Encode the price data (this will be part of the complete signature)
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  const priceData = abiCoder.encode(['int256', 'uint256'], [fundingRateScaled, timestamp]);
  
  // Create message hash according to EIP-191
  // This matches the hash generation in the TrustedSignerNode contract
  const messageHash = ethers.keccak256(
    ethers.solidityPacked(['string', 'int256', 'uint256'], [symbol, fundingRateScaled, timestamp])
  );
  
  // Sign the message hash
  const signature = await wallet.signMessage(ethers.getBytes(messageHash));
  
  // Combine the data and signature into a complete signature package
  return ethers.concat([priceData, signature]);
}

// Run the script
main().catch(console.error); 