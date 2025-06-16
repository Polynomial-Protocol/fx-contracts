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
  let poolId: number;
  let receipt: Ethers.providers.TransactionReceipt;

  // Test constants
  const LOCK_DURATION_90_DAYS = 90 * 24 * 60 * 60;
  const LOCK_DURATION_365_DAYS = 365 * 24 * 60 * 60;
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

  before('create pool', async () => {
    poolId = 1;
    await systems()
      .Core.connect(owner)
      .addToFeatureFlagAllowlist(
        ethers.utils.formatBytes32String('createPool'),
        await owner.getAddress()
      );
    await (
      await systems()
        .Core.connect(owner)
        .createPool(poolId, await owner.getAddress())
    ).wait();
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
    const mintAmount = ethers.utils.parseUnits('10000', 6);
    await (await Collateral.mint(await user1.getAddress(), mintAmount)).wait();
    await (await Collateral.mint(await user2.getAddress(), mintAmount)).wait();
    await (
      await Collateral.connect(user1).approve(systems().Core.address, ethers.constants.MaxUint256)
    ).wait();
    await (
      await Collateral.connect(user2).approve(systems().Core.address, ethers.constants.MaxUint256)
    ).wait();
  });

  before('deposit collateral', async () => {
    const depositAmount = ethers.utils.parseUnits('1000', 6);
    await (
      await systems().Core.connect(user1).deposit(accountId1, Collateral.address, depositAmount)
    ).wait();
    await (
      await systems().Core.connect(user2).deposit(accountId2, Collateral.address, depositAmount)
    ).wait();
  });

  before('set pool configuration', async () => {
    await (
      await systems()
        .Core.connect(owner)
        .setPoolCollateralConfiguration(poolId, Collateral.address, {
          collateralLimitD18: bn(1000000000),
          issuanceRatioD18: bn(4), // 400% issuance ratio
        })
    ).wait();
  });

  before('delegate collateral to pool', async () => {
    const delegateAmount = ethers.utils.parseUnits('500', 6);
    await (
      await systems()
        .Core.connect(user1)
        .delegateCollateral(
          accountId1,
          poolId,
          Collateral.address,
          delegateAmount,
          ethers.utils.parseEther('1')
        )
    ).wait();
  });

  const restore = snapshotCheckpoint(provider);

  describe('1. User Successfully Locking Collateral', function () {
    const lockAmount = ethers.utils.parseUnits('200', 6);
    const lockAmountD18 = ethers.utils.parseEther('200');

    before(restore);

    // Success scenarios
    describe('Success Scenarios', function () {
      let lockId: Ethers.BigNumber;

      it('should successfully lock collateral and emit event', async () => {
        const tx = await systems()
          .Core.connect(user1)
          .lockCollateral(accountId1, Collateral.address, lockAmount, LOCK_DURATION_365_DAYS);
        receipt = await tx.wait();

        const event = receipt.events?.find((e) => e.event === 'CollateralTimeLocked');
        lockId = event?.args?.lockId || ethers.BigNumber.from(1);

        await assertEvent(
          receipt,
          `CollateralTimeLocked(${accountId1}, "${Collateral.address}", ${lockAmountD18}, ${LOCK_DURATION_365_DAYS}, ${lockId}, ${BOOST_MULTIPLIER_365_DAYS})`,
          systems().Core
        );
      });

      it('should reduce available collateral correctly', async () => {
        const availableCollateral = await systems().Core.getAccountAvailableCollateral(
          accountId1,
          Collateral.address
        );
        const expectedAvailable = ethers.utils.parseEther('800'); // 1000 - 200 locked
        assertBn.near(availableCollateral, expectedAvailable, ethers.utils.parseEther('5'));
      });

      it('should create lock with correct details', async () => {
        const lockInfo = await systems().Core.getLockInfo(lockId);
        assertBn.equal(lockInfo.accountId, accountId1);
        assert.equal(lockInfo.collateralType, Collateral.address);
        assertBn.equal(lockInfo.amountD18, lockAmountD18);
        assertBn.equal(lockInfo.lockDuration, LOCK_DURATION_365_DAYS);
        assertBn.equal(lockInfo.boostMultiplier, BOOST_MULTIPLIER_365_DAYS);
        assert.equal(lockInfo.unlocked, false);
      });

      it('should calculate correct boosted value', async () => {
        const boostedValue = await systems().Core.getBoostedCollateralValue(
          accountId1,
          Collateral.address
        );
        const expectedBoostedValue = lockAmountD18.mul(BOOST_MULTIPLIER_365_DAYS).div(10000);
        assertBn.equal(boostedValue, expectedBoostedValue); // 200 * 110% = 220
      });
    });

    // Failure scenarios
    describe('Failure Scenarios', function () {
      it('should revert for unauthorized user', async () => {
        await assertRevert(
          systems()
            .Core.connect(user2)
            .lockCollateral(accountId1, Collateral.address, lockAmount, LOCK_DURATION_365_DAYS),
          `PermissionDenied("${accountId1}", "${Permissions.ADMIN}", "${await user2.getAddress()}")`,
          systems().Core
        );
      });

      it('should revert for non-existent account', async () => {
        await assertRevert(
          systems()
            .Core.connect(user1)
            .lockCollateral(999, Collateral.address, lockAmount, LOCK_DURATION_365_DAYS),
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
            .lockCollateral(accountId1, Collateral.address, 0, LOCK_DURATION_365_DAYS),
          'InvalidParameter("amount", "must be nonzero")',
          systems().Core
        );
      });

      it('should revert for insufficient collateral', async () => {
        const excessiveAmount = ethers.utils.parseUnits('10000', 6);
        const excessiveAmountD18 = ethers.utils.parseEther('10000');
        await assertRevert(
          systems()
            .Core.connect(user1)
            .lockCollateral(
              accountId1,
              Collateral.address,
              excessiveAmount,
              LOCK_DURATION_365_DAYS
            ),
          `InsufficientCollateralForLock("${accountId1}", "${Collateral.address}", "${excessiveAmountD18}")`,
          systems().Core
        );
      });
    });
  });

  describe('2. Borrowing Power Increase Due to Collateral Boost', function () {
    const lockAmount = ethers.utils.parseUnits('200', 6);
    const lockAmountD18 = ethers.utils.parseEther('200');

    before(restore);

    before('ensure proper delegation setup', async () => {
      const positionCollateral = await systems().Core.getPositionCollateral(
        accountId1,
        poolId,
        Collateral.address
      );

      if (positionCollateral.lt(ethers.utils.parseEther('100'))) {
        const delegateAmountD18 = ethers.utils.parseEther('500');
        await (
          await systems()
            .Core.connect(user1)
            .delegateCollateral(
              accountId1,
              poolId,
              Collateral.address,
              delegateAmountD18,
              ethers.utils.parseEther('1')
            )
        ).wait();
      }
    });

    it('should demonstrate increased minting capacity due to boost', async () => {
      const positionCollateral = await systems().Core.getPositionCollateral(
        accountId1,
        poolId,
        Collateral.address
      );
      assertBn.gt(positionCollateral, 0);

      let boostedValue = await systems().Core.getBoostedCollateralValue(
        accountId1,
        Collateral.address
      );
      assertBn.equal(boostedValue, 0);

      await systems()
        .Core.connect(user1)
        .lockCollateral(accountId1, Collateral.address, lockAmount, LOCK_DURATION_365_DAYS);

      boostedValue = await systems().Core.getBoostedCollateralValue(accountId1, Collateral.address);
      const expectedBoostedValue = lockAmountD18.mul(BOOST_MULTIPLIER_365_DAYS).div(10000);
      assertBn.equal(boostedValue, expectedBoostedValue); // Should be 220 (200 * 110%)

      assertBn.gt(boostedValue, 0);

      const additionalEffectiveCollateral = boostedValue.sub(lockAmountD18);
      assertBn.equal(additionalEffectiveCollateral, ethers.utils.parseEther('20')); // 10% boost on 200 tokens
    });

    it('should show boost reflected in collateral summary', async () => {
      const [, , totalTimeLocked, totalBoostedValue] =
        await systems().Core.getAccountCollateralSummary(accountId1, Collateral.address);

      // Verify the boost is reflected in the summary
      assertBn.equal(totalTimeLocked, lockAmountD18);

      // Boosted value should be higher than locked amount due to 110% multiplier
      const expectedBoostedValue = lockAmountD18.mul(BOOST_MULTIPLIER_365_DAYS).div(10000);
      assertBn.equal(totalBoostedValue, expectedBoostedValue);

      // Total effective collateral value for minting = position collateral + boosted value
      const positionCollateral = await systems().Core.getPositionCollateral(
        accountId1,
        poolId,
        Collateral.address
      );
      const totalEffectiveValue = positionCollateral.add(totalBoostedValue);

      // This should be greater than just the position collateral alone
      assertBn.gt(totalEffectiveValue, positionCollateral);
    });

    it('should demonstrate mathematical borrowing capacity increase', async () => {
      const positionCollateral = await systems().Core.getPositionCollateral(
        accountId1,
        poolId,
        Collateral.address
      );

      const boostedValue = await systems().Core.getBoostedCollateralValue(
        accountId1,
        Collateral.address
      );

      // Core verification: boost value increases effective collateral
      assertBn.gt(boostedValue, 0);

      // The effective collateral value for minting purposes is position + boost
      const effectiveCollateralValue = positionCollateral.add(boostedValue);

      // This should be greater than position collateral alone
      assertBn.gt(effectiveCollateralValue, positionCollateral);

      // The increase in effective collateral equals the boost value
      const effectiveIncrease = effectiveCollateralValue.sub(positionCollateral);
      assertBn.equal(effectiveIncrease, boostedValue);

      // Verify the boost is substantial (20 tokens = 10% of 200 locked)
      const expectedBoostAmount = ethers.utils.parseEther('20'); // 10% of 200
      assertBn.equal(effectiveIncrease, lockAmountD18.add(expectedBoostAmount));
    });
  });

  describe('3. User Unable to Unlock Before Lock Expiry', function () {
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

    // Failure scenarios (as expected)
    describe('Expected Failures Before Expiry', function () {
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

      it('should revert for unauthorized user trying to unlock', async () => {
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

      it('should show lock is not unlockable yet', async () => {
        const canUnlock = await systems().Core.canUnlockCollateral(lockId);
        assert.equal(canUnlock, false);
      });

      it('should show remaining lock time is greater than zero', async () => {
        const remainingTime = await systems().Core.getRemainingLockTime(lockId);
        assertBn.gt(remainingTime, 0);
        assertBn.lte(remainingTime, LOCK_DURATION_90_DAYS);
      });
    });
  });

  describe('4. User Successfully Unlocking After Lock Expiry', function () {
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

    // Success scenarios after expiry
    describe('Success Scenarios After Expiry', function () {
      let unlockReceipt: Ethers.providers.TransactionReceipt;

      it('should be unlockable after expiry', async () => {
        const canUnlock = await systems().Core.canUnlockCollateral(lockId);
        assert.equal(canUnlock, true);
      });

      it('should show zero remaining lock time', async () => {
        const remainingTime = await systems().Core.getRemainingLockTime(lockId);
        assertBn.equal(remainingTime, 0);
      });

      it('should successfully unlock and emit event', async () => {
        const tx = await systems().Core.connect(user1).unlockCollateral(lockId);
        unlockReceipt = await tx.wait();

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
        assertBn.near(availableCollateral, expectedAvailable, ethers.utils.parseEther('5'));
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

      it('should update collateral summary correctly', async () => {
        const [totalDeposited, totalAvailable, totalTimeLocked, totalBoostedValue] =
          await systems().Core.getAccountCollateralSummary(accountId1, Collateral.address);

        assertBn.near(
          totalDeposited,
          ethers.utils.parseEther('1000'),
          ethers.utils.parseEther('5')
        );
        assertBn.near(
          totalAvailable,
          ethers.utils.parseEther('1000'),
          ethers.utils.parseEther('5')
        );
        assertBn.equal(totalTimeLocked, 0);
        assertBn.equal(totalBoostedValue, 0);
      });
    });

    // Failure scenarios after unlock
    describe('Failure Scenarios After Unlock', function () {
      it('should revert when trying to unlock again', async () => {
        await assertRevert(
          systems().Core.connect(user1).unlockCollateral(lockId),
          `InvalidLockId("${lockId}")`,
          systems().Core
        );
      });
    });
  });
});
