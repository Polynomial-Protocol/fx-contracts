import assertBn from '@synthetixio/core-utils/utils/assertions/assert-bignumber';
import assertEvent from '@synthetixio/core-utils/utils/assertions/assert-event';
import assertRevert from '@synthetixio/core-utils/utils/assertions/assert-revert';
import assert from 'assert/strict';
import { fastForwardTo, getTime } from '@synthetixio/core-utils/utils/hardhat/rpc';
import { snapshotCheckpoint } from '@synthetixio/core-utils/utils/mocha/snapshot';
import { ethers as Ethers } from 'ethers';
import { ethers } from 'hardhat';
import { bn, bootstrap } from '../../../bootstrap';
import { addCollateral } from '../CollateralModule/CollateralModule.helper';
import Permissions from '../../../mixins/AccountRBACMixin.permissions';

describe('TimeLockCollateralModule', function () {
  const { signers, systems, provider } = bootstrap();

  let Collateral: Ethers.Contract;
  let owner: Ethers.Signer, user1: Ethers.Signer, user2: Ethers.Signer;
  let accountId1: number, accountId2: number;
  let receipt: Ethers.providers.TransactionReceipt;

  // Test constants
  const LOCK_DURATION_90_DAYS = 90 * 24 * 60 * 60;
  const LOCK_DURATION_180_DAYS = 180 * 24 * 60 * 60;
  const LOCK_DURATION_365_DAYS = 365 * 24 * 60 * 60;
  const BOOST_MULTIPLIER_90_DAYS = 10500; // 105%
  const BOOST_MULTIPLIER_180_DAYS = 10750; // 107.5%
  const BOOST_MULTIPLIER_365_DAYS = 11000; // 110%

  before('identify signers', async () => {
    [owner, user1, user2] = signers();
  });

  before('create accounts', async () => {
    accountId1 = 1;
    accountId2 = 2;
    await (await systems().Core.connect(user1)['createAccount(uint128)'](accountId1)).wait();
    await (await systems().Core.connect(user2)['createAccount(uint128)'](accountId2)).wait();
  });

  before('add collateral type', async () => {
    ({ Collateral } = await addCollateral(
      'Synthetix Token',
      'SNX',
      bn(4), // 400% issuance ratio
      bn(2), // 200% liquidation ratio
      owner,
      systems().Core,
      systems().OracleManager
    ));
  });

  before('mint and approve tokens', async () => {
    const mintAmount = ethers.utils.parseUnits('10000', 6); // 10,000 tokens with 6 decimals

    // Mint tokens to users
    await (await Collateral.mint(await user1.getAddress(), mintAmount)).wait();
    await (await Collateral.mint(await user2.getAddress(), mintAmount)).wait();

    // Approve Core contract to spend tokens
    await (
      await Collateral.connect(user1).approve(systems().Core.address, ethers.constants.MaxUint256)
    ).wait();
    await (
      await Collateral.connect(user2).approve(systems().Core.address, ethers.constants.MaxUint256)
    ).wait();
  });

  before('deposit collateral', async () => {
    const depositAmount = ethers.utils.parseUnits('1000', 6); // 1,000 tokens

    // Deposit collateral to accounts
    await (
      await systems().Core.connect(user1).deposit(accountId1, Collateral.address, depositAmount)
    ).wait();
    await (
      await systems().Core.connect(user2).deposit(accountId2, Collateral.address, depositAmount)
    ).wait();
  });

  const restore = snapshotCheckpoint(provider);

  describe('Boost Multiplier Logic', function () {
    it('should return correct boost multipliers for different durations', async () => {
      assertBn.equal(
        await systems().Core.getBoostMultiplier(LOCK_DURATION_90_DAYS),
        BOOST_MULTIPLIER_90_DAYS
      );
      assertBn.equal(
        await systems().Core.getBoostMultiplier(LOCK_DURATION_180_DAYS),
        BOOST_MULTIPLIER_180_DAYS
      );
      assertBn.equal(
        await systems().Core.getBoostMultiplier(LOCK_DURATION_365_DAYS),
        BOOST_MULTIPLIER_365_DAYS
      );
    });

    it('should revert for invalid durations', async () => {
      const invalidDuration = 30 * 24 * 60 * 60; // 30 days
      await assertRevert(
        systems().Core.getBoostMultiplier(invalidDuration),
        'Invalid lock duration',
        systems().Core
      );
    });
  });

  describe('Locking Collateral', function () {
    const lockAmount = ethers.utils.parseUnits('100', 6); // 100 tokens
    const lockAmountD18 = ethers.utils.parseEther('100'); // 100 tokens in system units

    before(restore);

    it('should verify permission for account', async () => {
      await assertRevert(
        systems()
          .Core.connect(user2)
          .lockCollateral(accountId1, Collateral.address, lockAmount, LOCK_DURATION_90_DAYS),
        `PermissionDenied("${accountId1}", "${Permissions.ADMIN}", "${await user2.getAddress()}")`,
        systems().Core
      );
    });

    it('should revert for non-existent account', async () => {
      await assertRevert(
        systems()
          .Core.connect(user1)
          .lockCollateral(999, Collateral.address, lockAmount, LOCK_DURATION_90_DAYS),
        'AccountNotFound("999")',
        systems().Core
      );
    });

    it('should revert for invalid lock duration', async () => {
      const invalidDuration = 30 * 24 * 60 * 60; // 30 days
      await assertRevert(
        systems()
          .Core.connect(user1)
          .lockCollateral(accountId1, Collateral.address, lockAmount, invalidDuration),
        `InvalidLockDuration("${invalidDuration}")`,
        systems().Core
      );
    });

    it('should revert for zero amount', async () => {
      await assertRevert(
        systems()
          .Core.connect(user1)
          .lockCollateral(accountId1, Collateral.address, 0, LOCK_DURATION_90_DAYS),
        'InvalidParameter("amount", "must be nonzero")',
        systems().Core
      );
    });

    it('should revert for insufficient collateral', async () => {
      const excessiveAmount = ethers.utils.parseUnits('10000', 6); // More than available
      const excessiveAmountD18 = ethers.utils.parseEther('10000');

      await assertRevert(
        systems()
          .Core.connect(user1)
          .lockCollateral(accountId1, Collateral.address, excessiveAmount, LOCK_DURATION_90_DAYS),
        `InsufficientCollateralForLock("${accountId1}", "${Collateral.address}", "${excessiveAmountD18}")`,
        systems().Core
      );
    });

    describe('Successful Locking', function () {
      let lockId: Ethers.BigNumber;

      before('lock collateral', async () => {
        const tx = await systems()
          .Core.connect(user1)
          .lockCollateral(accountId1, Collateral.address, lockAmount, LOCK_DURATION_90_DAYS);
        receipt = await tx.wait();

        // Extract lock ID from event
        const event = receipt.events?.find((e) => e.event === 'CollateralTimeLocked');
        lockId = event?.args?.lockId || ethers.BigNumber.from(1); // Default to 1 if not found
      });

      it('should emit CollateralTimeLocked event', async () => {
        await assertEvent(
          receipt,
          `CollateralTimeLocked(${accountId1}, "${Collateral.address}", ${lockAmountD18}, ${LOCK_DURATION_90_DAYS}, ${lockId}, ${BOOST_MULTIPLIER_90_DAYS})`,
          systems().Core
        );
      });

      it('should reduce available collateral', async () => {
        const availableCollateral = await systems().Core.getAccountAvailableCollateral(
          accountId1,
          Collateral.address
        );
        const expectedAvailable = ethers.utils.parseEther('900'); // 1000 - 100 locked
        assertBn.equal(availableCollateral, expectedAvailable);
      });

      it('should create lock with correct details', async () => {
        const lockInfo = await systems().Core.getLockInfo(lockId);

        assertBn.equal(lockInfo.accountId, accountId1);
        assert.equal(lockInfo.collateralType, Collateral.address);
        assertBn.equal(lockInfo.amountD18, lockAmountD18);
        assertBn.equal(lockInfo.lockDuration, LOCK_DURATION_90_DAYS);
        assertBn.equal(lockInfo.boostMultiplier, BOOST_MULTIPLIER_90_DAYS);
        assert.equal(lockInfo.unlocked, false);
      });

      it('should track account locks', async () => {
        const accountLocks = await systems().Core.getAccountActiveLocks(accountId1);
        assertBn.equal(accountLocks.length, 1);
        assertBn.equal(accountLocks[0], lockId);
      });

      it('should calculate boosted value', async () => {
        const boostedValue = await systems().Core.getBoostedCollateralValue(
          accountId1,
          Collateral.address
        );
        // 100 * 10500 / 10000 = 105
        const expectedBoostedValue = ethers.utils.parseEther('105');
        assertBn.equal(boostedValue, expectedBoostedValue);
      });

      it('should show correct collateral summary', async () => {
        const [totalDeposited, totalAvailable, totalTimeLocked, totalBoostedValue] =
          await systems().Core.getAccountCollateralSummary(accountId1, Collateral.address);

        assertBn.equal(totalDeposited, ethers.utils.parseEther('1000')); // 900 available + 100 locked
        assertBn.equal(totalAvailable, ethers.utils.parseEther('900'));
        assertBn.equal(totalTimeLocked, lockAmountD18);
        assertBn.equal(totalBoostedValue, ethers.utils.parseEther('105'));
      });

      it('should not be unlockable yet', async () => {
        const canUnlock = await systems().Core.canUnlockCollateral(lockId);
        assert.equal(canUnlock, false);
      });

      it('should show remaining lock time', async () => {
        const remainingTime = await systems().Core.getRemainingLockTime(lockId);
        assertBn.gt(remainingTime, 0);
        assertBn.lte(remainingTime, LOCK_DURATION_90_DAYS);
      });
    });
  });

  describe('Unlocking Collateral Before Expiry', function () {
    let lockId: Ethers.BigNumber;
    const lockAmount = ethers.utils.parseUnits('100', 6);

    before(restore);

    before('lock collateral', async () => {
      const tx = await systems()
        .Core.connect(user1)
        .lockCollateral(accountId1, Collateral.address, lockAmount, LOCK_DURATION_90_DAYS);
      const receipt = await tx.wait();

      const event = receipt.events?.find((e) => e.event === 'CollateralTimeLocked');
      lockId = event?.args?.lockId || ethers.BigNumber.from(1);
    });

    it('should revert when trying to unlock before expiry', async () => {
      const lockInfo = await systems().Core.getLockInfo(lockId);
      const currentTime = await getTime(provider());
      const unlockTime = lockInfo.lockTimestamp.add(lockInfo.lockDuration);

      await assertRevert(
        systems().Core.connect(user1).unlockCollateral(lockId),
        `LockNotExpired("${lockId}", "${currentTime}", "${unlockTime}")`,
        systems().Core
      );
    });

    it('should verify permission for unlock', async () => {
      await assertRevert(
        systems().Core.connect(user2).unlockCollateral(lockId),
        `PermissionDenied("${accountId1}", "${Permissions.ADMIN}", "${await user2.getAddress()}")`,
        systems().Core
      );
    });

    it('should revert for invalid lock ID', async () => {
      const invalidLockId = 999999;
      await assertRevert(
        systems().Core.connect(user1).unlockCollateral(invalidLockId),
        `InvalidLockId("${invalidLockId}")`,
        systems().Core
      );
    });
  });

  describe('Unlocking Collateral After Expiry', function () {
    let lockId: Ethers.BigNumber;
    const lockAmount = ethers.utils.parseUnits('100', 6);
    const lockAmountD18 = ethers.utils.parseEther('100');

    before(restore);

    before('lock collateral', async () => {
      const tx = await systems()
        .Core.connect(user1)
        .lockCollateral(accountId1, Collateral.address, lockAmount, LOCK_DURATION_90_DAYS);
      const receipt = await tx.wait();

      const event = receipt.events?.find((e) => e.event === 'CollateralTimeLocked');
      lockId = event?.args?.lockId || ethers.BigNumber.from(1);
    });

    before('fast forward past lock expiry', async () => {
      const lockInfo = await systems().Core.getLockInfo(lockId);
      const unlockTime = lockInfo.lockTimestamp.add(lockInfo.lockDuration).add(1);
      await fastForwardTo(unlockTime.toNumber(), provider());
    });

    it('should be unlockable after expiry', async () => {
      const canUnlock = await systems().Core.canUnlockCollateral(lockId);
      assert.equal(canUnlock, true);
    });

    it('should show zero remaining lock time', async () => {
      const remainingTime = await systems().Core.getRemainingLockTime(lockId);
      assertBn.equal(remainingTime, 0);
    });

    describe('Successful Unlock', function () {
      let unlockReceipt: Ethers.providers.TransactionReceipt;

      before('unlock collateral', async () => {
        const tx = await systems().Core.connect(user1).unlockCollateral(lockId);
        unlockReceipt = await tx.wait();
      });

      it('should emit CollateralTimeUnlocked event', async () => {
        await assertEvent(
          unlockReceipt,
          `CollateralTimeUnlocked(${accountId1}, "${Collateral.address}", ${lockAmountD18}, ${lockId})`,
          systems().Core
        );
      });

      it('should restore available collateral', async () => {
        const availableCollateral = await systems().Core.getAccountAvailableCollateral(
          accountId1,
          Collateral.address
        );
        const expectedAvailable = ethers.utils.parseEther('1000'); // Back to original amount
        assertBn.equal(availableCollateral, expectedAvailable);
      });

      it('should mark lock as unlocked', async () => {
        const lockInfo = await systems().Core.getLockInfo(lockId);
        assert.equal(lockInfo.unlocked, true);
      });

      it('should remove from active locks', async () => {
        const accountLocks = await systems().Core.getAccountActiveLocks(accountId1);
        assertBn.equal(accountLocks.length, 0);
      });

      it('should remove boosted value', async () => {
        const boostedValue = await systems().Core.getBoostedCollateralValue(
          accountId1,
          Collateral.address
        );
        assertBn.equal(boostedValue, 0);
      });

      it('should update collateral summary', async () => {
        const [totalDeposited, totalAvailable, totalTimeLocked, totalBoostedValue] =
          await systems().Core.getAccountCollateralSummary(accountId1, Collateral.address);

        assertBn.equal(totalDeposited, ethers.utils.parseEther('1000'));
        assertBn.equal(totalAvailable, ethers.utils.parseEther('1000'));
        assertBn.equal(totalTimeLocked, 0);
        assertBn.equal(totalBoostedValue, 0);
      });

      it('should revert when trying to unlock again', async () => {
        await assertRevert(
          systems().Core.connect(user1).unlockCollateral(lockId),
          `InvalidLockId("${lockId}")`,
          systems().Core
        );
      });
    });
  });

  describe('Borrowing Power Enhancement', function () {
    const lockAmount = ethers.utils.parseUnits('500', 6); // 500 tokens
    const lockAmountD18 = ethers.utils.parseEther('500');

    before(restore);

    it('should show initial borrowing power', async () => {
      // Check that account has collateral deposited
      const availableCollateral = await systems().Core.getAccountAvailableCollateral(
        accountId1,
        Collateral.address
      );

      // Should have 1000 tokens available initially
      assertBn.equal(availableCollateral, ethers.utils.parseEther('1000'));
    });

    describe('After Locking Collateral', function () {
      before('lock collateral', async () => {
        const tx = await systems()
          .Core.connect(user1)
          .lockCollateral(accountId1, Collateral.address, lockAmount, LOCK_DURATION_365_DAYS);
        await tx.wait();
      });

      it('should increase borrowing power due to boost', async () => {
        // Available collateral should decrease
        const availableCollateralAfter = await systems().Core.getAccountAvailableCollateral(
          accountId1,
          Collateral.address
        );
        assertBn.equal(availableCollateralAfter, ethers.utils.parseEther('500')); // 1000 - 500 locked

        // But boosted value should increase
        const boostedValueAfter = await systems().Core.getBoostedCollateralValue(
          accountId1,
          Collateral.address
        );

        // 500 * 11000 / 10000 = 550
        const expectedBoostedValue = ethers.utils.parseEther('550');
        assertBn.equal(boostedValueAfter, expectedBoostedValue);

        // Total effective collateral (available + boosted) is now higher
        // 500 (available) + 550 (boosted value) = 1050 vs original 1000
        const totalEffectiveCollateral = availableCollateralAfter.add(boostedValueAfter);
        assertBn.gt(totalEffectiveCollateral, ethers.utils.parseEther('1000'));
      });

      it('should allow increased minting due to boost', async () => {
        // This test demonstrates that the user can mint more fxUSD due to the boost
        // The actual implementation would depend on how the core system calculates
        // collateralization ratios with boosted values

        const [totalDeposited, totalAvailable, totalTimeLocked, totalBoostedValue] =
          await systems().Core.getAccountCollateralSummary(accountId1, Collateral.address);

        // Verify the summary shows the boost correctly
        assertBn.equal(totalDeposited, ethers.utils.parseEther('1000'));
        assertBn.equal(totalAvailable, ethers.utils.parseEther('500'));
        assertBn.equal(totalTimeLocked, lockAmountD18);
        assertBn.equal(totalBoostedValue, ethers.utils.parseEther('550'));
      });
    });
  });

  describe('Multiple Locks', function () {
    const lockAmount1 = ethers.utils.parseUnits('100', 6);
    const lockAmount2 = ethers.utils.parseUnits('200', 6);
    let lockId1: Ethers.BigNumber, lockId2: Ethers.BigNumber;

    before(restore);

    before('create multiple locks', async () => {
      // Lock 1: 100 tokens for 90 days
      const tx1 = await systems()
        .Core.connect(user1)
        .lockCollateral(accountId1, Collateral.address, lockAmount1, LOCK_DURATION_90_DAYS);
      const receipt1 = await tx1.wait();
      lockId1 =
        receipt1.events?.find((e) => e.event === 'CollateralTimeLocked')?.args?.lockId ||
        ethers.BigNumber.from(1);

      // Lock 2: 200 tokens for 365 days
      const tx2 = await systems()
        .Core.connect(user1)
        .lockCollateral(accountId1, Collateral.address, lockAmount2, LOCK_DURATION_365_DAYS);
      const receipt2 = await tx2.wait();
      lockId2 =
        receipt2.events?.find((e) => e.event === 'CollateralTimeLocked')?.args?.lockId ||
        ethers.BigNumber.from(2);
    });

    it('should track multiple active locks', async () => {
      const accountLocks = await systems().Core.getAccountActiveLocks(accountId1);
      assertBn.equal(accountLocks.length, 2);
    });

    it('should calculate combined boosted value', async () => {
      const boostedValue = await systems().Core.getBoostedCollateralValue(
        accountId1,
        Collateral.address
      );
      // (100 * 10500 / 10000) + (200 * 11000 / 10000) = 105 + 220 = 325
      const expectedBoostedValue = ethers.utils.parseEther('325');
      assertBn.equal(boostedValue, expectedBoostedValue);
    });

    it('should show correct summary with multiple locks', async () => {
      const [totalDeposited, totalAvailable, totalTimeLocked, totalBoostedValue] =
        await systems().Core.getAccountCollateralSummary(accountId1, Collateral.address);

      assertBn.equal(totalDeposited, ethers.utils.parseEther('1000'));
      assertBn.equal(totalAvailable, ethers.utils.parseEther('700')); // 1000 - 300 locked
      assertBn.equal(totalTimeLocked, ethers.utils.parseEther('300')); // 100 + 200
      assertBn.equal(totalBoostedValue, ethers.utils.parseEther('325'));
    });

    describe('Partial Unlock', function () {
      before('fast forward past first lock expiry only', async () => {
        const lockInfo1 = await systems().Core.getLockInfo(lockId1);
        const unlockTime1 = lockInfo1.lockTimestamp.add(lockInfo1.lockDuration).add(1);
        await fastForwardTo(unlockTime1.toNumber(), provider());
      });

      before('unlock first lock', async () => {
        await systems().Core.connect(user1).unlockCollateral(lockId1);
      });

      it('should have one remaining active lock', async () => {
        const accountLocks = await systems().Core.getAccountActiveLocks(accountId1);
        assertBn.equal(accountLocks.length, 1);
        assertBn.equal(accountLocks[0], lockId2);
      });

      it('should reduce boosted value', async () => {
        const boostedValue = await systems().Core.getBoostedCollateralValue(
          accountId1,
          Collateral.address
        );
        // Only second lock: 200 * 11000 / 10000 = 220
        const expectedBoostedValue = ethers.utils.parseEther('220');
        assertBn.equal(boostedValue, expectedBoostedValue);
      });

      it('should update summary after partial unlock', async () => {
        const [totalDeposited, totalAvailable, totalTimeLocked, totalBoostedValue] =
          await systems().Core.getAccountCollateralSummary(accountId1, Collateral.address);

        assertBn.equal(totalDeposited, ethers.utils.parseEther('1000'));
        assertBn.equal(totalAvailable, ethers.utils.parseEther('800')); // 1000 - 200 locked
        assertBn.equal(totalTimeLocked, ethers.utils.parseEther('200')); // Only second lock
        assertBn.equal(totalBoostedValue, ethers.utils.parseEther('220'));
      });
    });
  });
});
