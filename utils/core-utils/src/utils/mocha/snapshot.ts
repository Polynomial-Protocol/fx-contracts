import { ethers } from 'ethers';

export function snapshotCheckpoint(provider: () => ethers.providers.JsonRpcProvider) {
  let snapshotId: number | null = null;

  // Lazy snapshot creation - only create on first restore call
  const restore = async () => {
    const prov = provider();
    if (snapshotId !== null) {
      // Restore to existing snapshot
      await prov.send('evm_revert', [snapshotId]);
    }
    // Always create a new snapshot for next restore
    snapshotId = await prov.send('evm_snapshot', []);
  };

  return restore;
}
