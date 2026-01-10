//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "../../interfaces/IUnsecuredCreditModule.sol";
import "../../interfaces/IUSDTokenModule.sol";
import "../../storage/UnsecuredCredit.sol";
import "../../storage/Market.sol";

import "@synthetixio/core-modules/contracts/storage/AssociatedSystem.sol";
import "@synthetixio/core-modules/contracts/storage/FeatureFlag.sol";

import "@synthetixio/core-contracts/contracts/utils/DecimalMath.sol";
import "@synthetixio/core-contracts/contracts/utils/SafeCast.sol";
import "@synthetixio/core-contracts/contracts/utils/ERC2771Context.sol";
import "@synthetixio/core-contracts/contracts/ownership/OwnableStorage.sol";
import "@synthetixio/core-contracts/contracts/errors/ParameterError.sol";

contract UnsecuredCreditModule is IUnsecuredCreditModule {
    using DecimalMath for uint256;
    using SafeCastU256 for uint256;
    using SafeCastI256 for int256;
    using SafeCastU128 for uint128;
    using SafeCastI128 for int128;
    using AssociatedSystem for AssociatedSystem.Data;

    bytes32 private constant _USD_TOKEN = "USDToken";
    bytes32 private constant _BORROW_FEATURE_FLAG = "borrowUnsecured";
    bytes32 private constant _REPAY_FEATURE_FLAG = "repayUnsecured";

    // ----------------
    // Admin
    // ----------------

    function setGlobalCap(uint256 capD18) external override {
        OwnableStorage.onlyOwner();
        UnsecuredCredit.load().globalDebtCapD18 = capD18;
        emit GlobalCapSet(capD18);
    }

    function setGlobalPause(bool paused) external override {
        OwnableStorage.onlyOwner();
        UnsecuredCredit.load().globalPaused = paused;
        emit GlobalPauseSet(paused);
    }

    function configureMarket(
        uint128 marketId,
        MarketConfiguration calldata config
    ) external override {
        OwnableStorage.onlyOwner();
        _validateConfig(config);

        UnsecuredCredit.Data storage data = UnsecuredCredit.load();
        UnsecuredCredit.MarketConfig storage stored = data.marketConfig[marketId];

        // Accrue any pending interest before changing parameters to avoid losing it.
        if (stored.isWhitelisted) {
            accrue(marketId);
        }

        stored.isWhitelisted = config.isWhitelisted;
        stored.marketPaused = config.marketPaused;
        stored.debtCapD18 = config.debtCapD18;
        stored.ratePerSecondD18 = config.ratePerSecondD18;
        stored.epochLength = config.epochLength;
        stored.epochLimitD18 = config.epochLimitD18;

        UnsecuredCredit.MarketState storage state = data.marketState[marketId];
        // solhint-disable-next-line numcast/safe-cast
        state.lastAccrual = uint64(block.timestamp);
        if (config.epochLength != 0) {
            // solhint-disable-next-line numcast/safe-cast
            state.lastEpoch = uint64(block.timestamp / config.epochLength);
            state.epochBorrowedD18 = 0;
        }

        emit MarketConfigured(marketId, config);
    }

    // ----------------
    // Core flows
    // ----------------

    function accrue(uint128 marketId) public override returns (uint256 accruedD18) {
        UnsecuredCredit.Data storage data = UnsecuredCredit.load();
        (
            UnsecuredCredit.MarketConfig storage config,
            UnsecuredCredit.MarketState storage state
        ) = _loadConfig(data, marketId);

        if (state.lastAccrual == 0) {
            // solhint-disable-next-line numcast/safe-cast
            state.lastAccrual = uint64(block.timestamp);
            return 0;
        }

        if (config.ratePerSecondD18 == 0) {
            // solhint-disable-next-line numcast/safe-cast
            state.lastAccrual = uint64(block.timestamp);
            return 0;
        }

        uint256 dt = block.timestamp - state.lastAccrual;
        if (dt == 0) {
            return 0;
        }

        uint256 baseDebt = state.principalD18 + state.accruedInterestD18 + state.badDebtD18;
        if (baseDebt == 0) {
            // solhint-disable-next-line numcast/safe-cast
            state.lastAccrual = uint64(block.timestamp);
            return 0;
        }

        accruedD18 = baseDebt.mulDecimal(config.ratePerSecondD18) * dt;
        if (accruedD18 > 0) {
            state.accruedInterestD18 += accruedD18;
            data.totalDebtD18 += accruedD18;

            // reflect in market issuance so downstream accounting sees the increased debt
            Market.Data storage market = Market.load(marketId);
            market.netIssuanceD18 += accruedD18.toInt().to128();
        }

        // solhint-disable-next-line numcast/safe-cast
        state.lastAccrual = uint64(block.timestamp);
    }

    function borrowUnsecured(
        uint128 marketId,
        address target,
        uint256 amountD18
    ) external override returns (uint256 interestAccruedD18) {
        FeatureFlag.ensureAccessToFeature(_BORROW_FEATURE_FLAG);
        UnsecuredCredit.Data storage data = UnsecuredCredit.load();
        (
            Market.Data storage market,
            UnsecuredCredit.MarketConfig storage config,
            UnsecuredCredit.MarketState storage state
        ) = _loadMarket(data, marketId);

        _ensureNotPaused(data, config, marketId);
        _ensureMarketCaller(market, marketId);

        if (amountD18 == 0) {
            revert ParameterError.InvalidParameter("amount", "must be greater than zero");
        }

        _rollEpoch(config, state);

        interestAccruedD18 = accrue(marketId);

        uint256 available = _availableToBorrow(data, config, state);
        if (amountD18 > available) {
            revert CapExceeded(amountD18, available);
        }

        if (config.epochLimitD18 != 0) {
            state.epochBorrowedD18 += amountD18;
        }

        state.principalD18 += amountD18;
        data.totalDebtD18 += amountD18;

        market.netIssuanceD18 += amountD18.toInt().to128();

        IUSDTokenModule usdToken = IUSDTokenModule(
            address(AssociatedSystem.load(_USD_TOKEN).asToken())
        );
        usdToken.mint(target, amountD18);

        emit Borrowed(
            marketId,
            amountD18,
            state.principalD18,
            state.accruedInterestD18,
            target,
            ERC2771Context._msgSender()
        );
    }

    function repayUnsecured(
        uint128 marketId,
        address from,
        uint256 amountD18
    )
        external
        override
        returns (uint256 interestRepaidD18, uint256 principalRepaidD18, uint256 badDebtRepaidD18)
    {
        FeatureFlag.ensureAccessToFeature(_REPAY_FEATURE_FLAG);
        UnsecuredCredit.Data storage data = UnsecuredCredit.load();
        (
            Market.Data storage market,
            UnsecuredCredit.MarketConfig storage config,
            UnsecuredCredit.MarketState storage state
        ) = _loadMarket(data, marketId);

        _ensureNotPaused(data, config, marketId);
        _ensureMarketCaller(market, marketId);

        accrue(marketId);

        uint256 totalDebt = state.accruedInterestD18 + state.principalD18 + state.badDebtD18;
        if (amountD18 > totalDebt) {
            amountD18 = totalDebt;
        }
        IUSDTokenModule usdToken = IUSDTokenModule(
            address(AssociatedSystem.load(_USD_TOKEN).asToken())
        );
        usdToken.burnWithAllowance(from, ERC2771Context._msgSender(), amountD18);

        uint256 remaining = amountD18;

        if (state.accruedInterestD18 > 0) {
            interestRepaidD18 = remaining > state.accruedInterestD18
                ? state.accruedInterestD18
                : remaining;
            state.accruedInterestD18 -= interestRepaidD18;
            remaining -= interestRepaidD18;
        }

        if (remaining > 0 && state.principalD18 > 0) {
            principalRepaidD18 = remaining > state.principalD18 ? state.principalD18 : remaining;
            state.principalD18 -= principalRepaidD18;
            remaining -= principalRepaidD18;
        }

        if (remaining > 0 && state.badDebtD18 > 0) {
            badDebtRepaidD18 = remaining > state.badDebtD18 ? state.badDebtD18 : remaining;
            state.badDebtD18 -= badDebtRepaidD18;
            remaining -= badDebtRepaidD18;
        }

        uint256 repaidTotal = interestRepaidD18 + principalRepaidD18 + badDebtRepaidD18;
        if (repaidTotal > 0) {
            data.totalDebtD18 = repaidTotal > data.totalDebtD18
                ? 0
                : data.totalDebtD18 - repaidTotal;
            int128 repaidInt = repaidTotal.toInt().to128();
            market.netIssuanceD18 = market.netIssuanceD18 > repaidInt
                ? market.netIssuanceD18 - repaidInt
                : int128(0); // solhint-disable-line numcast/safe-cast
        }

        emit Repaid(
            marketId,
            amountD18,
            state.principalD18,
            state.accruedInterestD18,
            state.badDebtD18,
            from,
            ERC2771Context._msgSender()
        );
    }

    // ----------------
    // Views
    // ----------------

    function getMarketUnsecuredDebt(
        uint128 marketId
    )
        external
        view
        override
        returns (uint256 principalD18, uint256 accruedInterestD18, uint256 badDebtD18)
    {
        UnsecuredCredit.Data storage data = UnsecuredCredit.load();
        (
            UnsecuredCredit.MarketConfig storage config,
            UnsecuredCredit.MarketState storage state
        ) = _loadConfig(data, marketId);

        principalD18 = state.principalD18;
        badDebtD18 = state.badDebtD18;
        accruedInterestD18 = _accruedView(state, config);
    }

    function getAvailableToBorrow(
        uint128 marketId
    ) external view override returns (uint256 amountD18) {
        UnsecuredCredit.Data storage data = UnsecuredCredit.load();
        (
            UnsecuredCredit.MarketConfig storage config,
            UnsecuredCredit.MarketState storage state
        ) = _loadConfig(data, marketId);
        amountD18 = _availableToBorrowView(data, config, state);
    }

    // ----------------
    // Helpers
    // ----------------

    function _availableToBorrow(
        UnsecuredCredit.Data storage data,
        UnsecuredCredit.MarketConfig storage config,
        UnsecuredCredit.MarketState storage state
    ) private view returns (uint256) {
        uint256 marketCap = _remaining(
            config.debtCapD18,
            state.principalD18 + state.accruedInterestD18 + state.badDebtD18
        );
        uint256 globalCap = _remaining(data.globalDebtCapD18, data.totalDebtD18);

        uint256 cap = _min(marketCap, globalCap);
        if (config.epochLength == 0 || config.epochLimitD18 == 0) {
            return cap;
        }

        uint256 remainingEpoch = _remaining(config.epochLimitD18, state.epochBorrowedD18);
        return _min(cap, remainingEpoch);
    }

    function _availableToBorrowView(
        UnsecuredCredit.Data storage data,
        UnsecuredCredit.MarketConfig storage config,
        UnsecuredCredit.MarketState storage state
    ) private view returns (uint256) {
        uint256 accruedInterestD18 = _accruedView(state, config);
        uint256 marketCap = _remaining(
            config.debtCapD18,
            state.principalD18 + accruedInterestD18 + state.badDebtD18
        );
        uint256 globalCap = _remaining(data.globalDebtCapD18, data.totalDebtD18);

        uint256 cap = _min(marketCap, globalCap);
        if (config.epochLength == 0 || config.epochLimitD18 == 0) {
            return cap;
        }

        // solhint-disable-next-line numcast/safe-cast
        uint256 currentEpoch = uint256(state.lastEpoch);
        if (config.epochLength != 0) {
            uint256 epochNow = block.timestamp / config.epochLength;
            if (epochNow != currentEpoch) {
                return _min(cap, config.epochLimitD18);
            }
        }

        uint256 remainingEpoch = _remaining(config.epochLimitD18, state.epochBorrowedD18);
        return _min(cap, remainingEpoch);
    }

    function _accruedView(
        UnsecuredCredit.MarketState storage state,
        UnsecuredCredit.MarketConfig storage config
    ) private view returns (uint256) {
        if (state.lastAccrual == 0 || config.ratePerSecondD18 == 0) {
            return state.accruedInterestD18;
        }

        uint256 dt = block.timestamp - state.lastAccrual;
        if (dt == 0) {
            return state.accruedInterestD18;
        }

        uint256 baseDebt = state.principalD18 + state.accruedInterestD18 + state.badDebtD18;
        if (baseDebt == 0) {
            return state.accruedInterestD18;
        }

        uint256 accruedD18 = baseDebt.mulDecimal(config.ratePerSecondD18) * dt;
        return state.accruedInterestD18 + accruedD18;
    }

    function _rollEpoch(
        UnsecuredCredit.MarketConfig storage config,
        UnsecuredCredit.MarketState storage state
    ) private {
        if (config.epochLength == 0) {
            return;
        }

        // solhint-disable-next-line numcast/safe-cast
        uint64 currentEpoch = uint64(block.timestamp / config.epochLength);
        if (state.lastEpoch != currentEpoch) {
            state.lastEpoch = currentEpoch;
            state.epochBorrowedD18 = 0;
        }
    }

    function _loadMarket(
        UnsecuredCredit.Data storage data,
        uint128 marketId
    )
        private
        view
        returns (
            Market.Data storage market,
            UnsecuredCredit.MarketConfig storage config,
            UnsecuredCredit.MarketState storage state
        )
    {
        market = Market.load(marketId);
        if (market.marketAddress == address(0)) {
            revert InvalidMarket(marketId);
        }

        config = data.marketConfig[marketId];
        state = data.marketState[marketId];

        if (!config.isWhitelisted) {
            revert NotWhitelisted(marketId);
        }
    }

    function _loadConfig(
        UnsecuredCredit.Data storage data,
        uint128 marketId
    )
        private
        view
        returns (
            UnsecuredCredit.MarketConfig storage config,
            UnsecuredCredit.MarketState storage state
        )
    {
        config = data.marketConfig[marketId];
        state = data.marketState[marketId];
        if (!config.isWhitelisted) {
            revert NotWhitelisted(marketId);
        }
    }

    function _ensureNotPaused(
        UnsecuredCredit.Data storage data,
        UnsecuredCredit.MarketConfig storage config,
        uint128 marketId
    ) private view {
        if (data.globalPaused) {
            revert GlobalPaused();
        }
        if (config.marketPaused) {
            revert MarketPaused(marketId);
        }
    }

    function _ensureMarketCaller(Market.Data storage market, uint128 marketId) private view {
        if (ERC2771Context._msgSender() != market.marketAddress) {
            revert UnauthorizedMarket(ERC2771Context._msgSender(), marketId);
        }
    }

    function _validateConfig(MarketConfiguration calldata config) private pure {
        if (config.epochLimitD18 != 0 && config.epochLength == 0) {
            revert InvalidParameter("epochLength", "cannot be zero when epochLimit set");
        }
        if (config.debtCapD18 == 0) {
            revert InvalidParameter("debtCapD18", "must be greater than zero");
        }
    }

    function _remaining(uint256 cap, uint256 used) private pure returns (uint256) {
        if (cap == 0 || used >= cap) {
            return 0;
        }
        return cap - used;
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
