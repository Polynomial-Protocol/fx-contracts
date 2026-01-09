import { ethers } from 'ethers';

export function snapshotCheckpoint(provider: () => ethers.providers.JsonRpcProvider) {
  let snapshotId: number;

  before('snapshot', async function () {
    // Increase timeout for snapshot creation
    this.timeout(30000);
    snapshotId = await provider().send('evm_snapshot', []);
  });

  const restore = async () => {
    await provider().send('evm_revert', [snapshotId]);
    snapshotId = await provider().send('evm_snapshot', []);
  };

  return restore;
}
