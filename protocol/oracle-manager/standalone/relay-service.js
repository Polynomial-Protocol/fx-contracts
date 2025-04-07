#!/usr/bin/env node

/**
 * Binance Funding Rate Relay Service
 * 
 * A demo service that automatically fetches and signs Binance funding rates
 * and provides a simple web dashboard to view the latest data.
 * 
 * Usage:
 *   node relay-service.js <symbol> <private_key> [port]
 * 
 * Example:
 *   node relay-service.js BTCUSDT 0x123...456 3000
 */

const { ethers } = require('ethers');
const axios = require('axios');
const express = require('express');
const path = require('path');

// Constants
const BINANCE_API_URL = 'https://fapi.binance.com/fapi/v1/premiumIndex';
const UPDATE_INTERVAL = 60000; // Fetch every 60 seconds
const DEFAULT_PORT = 3000;

// Storage for the latest data
let latestData = {
  symbol: null,
  fundingRate: null,
  fundingRateScaled: null,
  timestamp: null,
  nextFundingTime: null,
  signerAddress: null,
  signedData: null,
  nodeParameters: null,
  lastUpdated: null,
  history: []
};

async function main() {
  // Parse command line arguments
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: node relay-service.js <symbol> <private_key> [port]');
    process.exit(1);
  }

  const symbol = args[0].toUpperCase();
  const privateKey = args[1];
  const port = args[2] || DEFAULT_PORT;
  
  try {
    // Create a wallet from the private key
    const wallet = new ethers.Wallet(privateKey);
    console.log(`Signer address: ${wallet.address}`);
    latestData.signerAddress = wallet.address;
    latestData.symbol = symbol;
    
    // Start the web server
    const app = setupWebServer(port);
    
    // Start the periodic update
    console.log(`Starting periodic updates for ${symbol} every ${UPDATE_INTERVAL/1000} seconds`);
    updateFundingRate(symbol, wallet);
    setInterval(() => updateFundingRate(symbol, wallet), UPDATE_INTERVAL);
    
  } catch (error) {
    console.error('Error:', error.message || error);
    process.exit(1);
  }
}

/**
 * Update the funding rate data
 */
async function updateFundingRate(symbol, wallet) {
  try {
    console.log(`Fetching funding rate for ${symbol}...`);
    
    // Fetch the funding rate from Binance
    const fundingRate = await fetchFundingRate(symbol);
    
    // Convert funding rate to the expected format (multiplied by 10^18)
    const fundingRateScaled = ethers.parseEther(fundingRate.lastFundingRate.toString());
    
    // Get the current timestamp
    const timestamp = Math.floor(Date.now() / 1000);
    
    // Create and sign the message
    const signedData = await signFundingRate(wallet, symbol, fundingRateScaled, timestamp);
    
    // Generate the node parameters
    const nodeParameters = ethers.AbiCoder.defaultAbiCoder().encode(
      ['string', 'bytes'],
      [symbol, signedData]
    );
    
    // Update the latest data
    latestData.fundingRate = fundingRate.lastFundingRate;
    latestData.fundingRateScaled = fundingRateScaled.toString();
    latestData.timestamp = timestamp;
    latestData.nextFundingTime = fundingRate.nextFundingTime;
    latestData.signedData = signedData;
    latestData.nodeParameters = nodeParameters;
    latestData.lastUpdated = new Date().toISOString();
    
    // Add to history (keep last 10 entries)
    latestData.history.unshift({
      timestamp: timestamp,
      date: new Date(timestamp * 1000).toISOString(),
      fundingRate: fundingRate.lastFundingRate,
      signedData: signedData.slice(0, 50) + '...' // Truncate for display
    });
    
    if (latestData.history.length > 10) {
      latestData.history.pop();
    }
    
    console.log(`Updated funding rate: ${fundingRate.lastFundingRate}`);
  } catch (error) {
    console.error('Error updating funding rate:', error.message || error);
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

/**
 * Set up the web server
 */
function setupWebServer(port) {
  const app = express();
  
  // API endpoint for the latest data
  app.get('/api/latest', (req, res) => {
    res.json(latestData);
  });
  
  // Serve the HTML dashboard
  app.get('/', (req, res) => {
    res.send(generateDashboardHtml());
  });
  
  // Start the server
  app.listen(port, () => {
    console.log(`Relay service running at http://localhost:${port}`);
  });
  
  return app;
}

/**
 * Generate the HTML for the dashboard
 */
function generateDashboardHtml() {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Binance Funding Rate Oracle Demo</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/css/bootstrap.min.css" rel="stylesheet">
  <style>
    body { padding: 20px; background-color: #f8f9fa; }
    .card { margin-bottom: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
    .refresh-btn { margin-left: 10px; }
    pre { background-color: #f0f0f0; padding: 10px; border-radius: 5px; overflow-x: auto; }
    .funding-rate { font-size: 2.5rem; font-weight: bold; }
    .positive { color: #28a745; }
    .negative { color: #dc3545; }
    .neutral { color: #17a2b8; }
    .data-age { font-style: italic; color: #6c757d; }
    .history-item { border-bottom: 1px solid #dee2e6; padding: 8px 0; }
    .loading { opacity: 0.6; }
  </style>
</head>
<body>
  <div class="container">
    <div class="row mb-4">
      <div class="col">
        <h1>Binance Funding Rate Oracle
          <button class="btn btn-primary btn-sm refresh-btn" onclick="fetchLatestData()">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="currentColor" class="bi bi-arrow-clockwise" viewBox="0 0 16 16">
              <path fill-rule="evenodd" d="M8 3a5 5 0 1 0 4.546 2.914.5.5 0 0 1 .908-.417A6 6 0 1 1 8 2v1z"/>
              <path d="M8 4.466V.534a.25.25 0 0 1 .41-.192l2.36 1.966c.12.1.12.284 0 .384L8.41 4.658A.25.25 0 0 1 8 4.466z"/>
            </svg>
            Refresh
          </button>
        </h1>
        <p class="lead">Real-time funding rate data from Binance, signed and ready for on-chain use.</p>
      </div>
    </div>

    <div class="row">
      <div class="col-md-6">
        <div class="card">
          <div class="card-header bg-primary text-white">
            <h5 class="card-title mb-0">Current Funding Rate</h5>
          </div>
          <div class="card-body">
            <div class="d-flex justify-content-between align-items-center mb-3">
              <h2 id="symbol">--</h2>
              <span class="data-age" id="last-updated">--</span>
            </div>
            <div class="funding-rate" id="funding-rate">--</div>
            <p>Next funding: <span id="next-funding">--</span></p>
          </div>
        </div>

        <div class="card">
          <div class="card-header bg-secondary text-white">
            <h5 class="card-title mb-0">Signer Details</h5>
          </div>
          <div class="card-body">
            <p><strong>Address:</strong> <span id="signer-address">--</span></p>
            <p><strong>Timestamp:</strong> <span id="timestamp">--</span></p>
          </div>
        </div>
      </div>

      <div class="col-md-6">
        <div class="card">
          <div class="card-header bg-dark text-white">
            <h5 class="card-title mb-0">Oracle Data</h5>
          </div>
          <div class="card-body">
            <h6>Signed Data (hex):</h6>
            <pre id="signed-data" class="small">--</pre>
            <h6>Node Parameters (hex):</h6>
            <pre id="node-parameters" class="small">--</pre>
          </div>
        </div>
      </div>
    </div>

    <div class="row mt-4">
      <div class="col">
        <div class="card">
          <div class="card-header bg-info text-white">
            <h5 class="card-title mb-0">Historical Data</h5>
          </div>
          <div class="card-body">
            <div id="history-container">
              <p>Loading history...</p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <footer class="mt-5 pt-3 text-muted border-top">
      <div class="row">
        <div class="col-md-6">
          <p>Polynomial Hackathon 2024 - Trusted Signer Oracle Demo</p>
        </div>
        <div class="col-md-6 text-md-end">
          <p>Auto-refreshes every ${UPDATE_INTERVAL / 1000} seconds</p>
        </div>
      </div>
    </footer>
  </div>

  <script>
    // Fetch latest data on load and periodically
    fetchLatestData();
    setInterval(fetchLatestData, ${UPDATE_INTERVAL});
    
    // Format the funding rate for display
    function formatFundingRate(rate) {
      const percentage = (rate * 100).toFixed(4) + '%';
      const cssClass = rate > 0 ? 'positive' : (rate < 0 ? 'negative' : 'neutral');
      const prefix = rate > 0 ? '+' : '';
      return '<span class="' + cssClass + '">' + prefix + percentage + '</span>';
    }
    
    // Calculate time ago string
    function timeAgo(timestamp) {
      const seconds = Math.floor((new Date() - new Date(timestamp)) / 1000);
      if (seconds < 60) return seconds + " seconds ago";
      const minutes = Math.floor(seconds / 60);
      if (minutes < 60) return minutes + " minutes ago";
      const hours = Math.floor(minutes / 60);
      if (hours < 24) return hours + " hours ago";
      const days = Math.floor(hours / 24);
      return days + " days ago";
    }
    
    // Truncate long strings
    function truncate(str, length = 10) {
      if (!str) return "";
      if (str.length <= length * 2) return str;
      return str.substring(0, length) + '...' + str.substring(str.length - length);
    }
    
    // Fetch the latest data from the API
    function fetchLatestData() {
      // Add loading indicators
      document.getElementById('funding-rate').classList.add('loading');
      
      fetch('/api/latest')
        .then(response => response.json())
        .then(data => {
          // Remove loading indicators
          document.getElementById('funding-rate').classList.remove('loading');
          
          // Update the UI with the latest data
          if (data.symbol) {
            document.getElementById('symbol').textContent = data.symbol;
            document.getElementById('funding-rate').innerHTML = formatFundingRate(data.fundingRate);
            document.getElementById('signer-address').textContent = truncate(data.signerAddress, 20);
            document.getElementById('timestamp').textContent = new Date(data.timestamp * 1000).toLocaleString();
            document.getElementById('last-updated').textContent = data.lastUpdated ? timeAgo(data.lastUpdated) : '--';
            document.getElementById('next-funding').textContent = data.nextFundingTime ? new Date(data.nextFundingTime).toLocaleString() : '--';
            document.getElementById('signed-data').textContent = truncate(data.signedData, 30);
            document.getElementById('node-parameters').textContent = truncate(data.nodeParameters, 30);
            
            // Update history
            const historyHtml = data.history.length > 0 
              ? data.history.map((item, index) => 
                  '<div class="history-item">' +
                    '<div class="d-flex justify-content-between">' +
                      '<span>' + new Date(item.date).toLocaleString() + '</span>' +
                      '<span>' + formatFundingRate(item.fundingRate) + '</span>' +
                    '</div>' +
                  '</div>'
                ).join('')
              : '<p>No history available yet</p>';
            
            document.getElementById('history-container').innerHTML = historyHtml;
          }
        })
        .catch(error => {
          console.error('Error fetching latest data:', error);
          document.getElementById('funding-rate').classList.remove('loading');
        });
    }
  </script>
</body>
</html>
  `;
}

// Run the script
main().catch(console.error); 