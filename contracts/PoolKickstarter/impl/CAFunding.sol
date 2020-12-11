/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import {SafeMath} from "../../lib/SafeMath.sol";
import {SafeERC20} from "../../lib/SafeERC20.sol";
import {DecimalMath} from "../../lib/DecimalMath.sol";
import {IERC20} from "../../intf/IERC20.sol";
import {IDVM} from "../../DODOVendingMachine/intf/IDVM.sol";
import {IDVMFactory} from "../../Factory/DVMFactory.sol";
import {CAStorage} from "./CAStorage.sol";
import {PMMPricing} from "../../lib/PMMPricing.sol";

contract CAFunding is CAStorage {
    using SafeERC20 for IERC20;

    // ============ BID & CALM PHASE ============

    modifier isBidderAllow(address bidder) {
        require(_BIDDER_PERMISSION_.isAllowed(bidder), "BIDDER_NOT_ALLOWED");
        _;
    }

    function bid(address to) external phaseBid preventReentrant isBidderAllow(to) {
        uint256 input = _getQuoteInput();
        uint256 mtFee = DecimalMath.mulFloor(input, _MT_FEE_RATE_MODEL_.getFeeRate(to));
        _transferQuoteOut(_MAINTAINER_, mtFee);
        _mintShares(to, input.sub(mtFee));
        _sync();
    }

    function cancel(address assetTo, uint256 amount) external phaseBidOrCalm preventReentrant {
        require(_SHARES_[msg.sender] >= amount, "SHARES_NOT_ENOUGH");
        _burnShares(msg.sender, amount);
        _transferQuoteOut(assetTo, amount);
        _sync();
    }

    function _mintShares(address to, uint256 amount) internal {
        _SHARES_[to] = _SHARES_[to].add(amount);
        _TOTAL_SHARES_ = _TOTAL_SHARES_.add(amount);
    }

    function _burnShares(address from, uint256 amount) internal {
        _SHARES_[from] = _SHARES_[from].sub(amount);
        _TOTAL_SHARES_ = _TOTAL_SHARES_.sub(amount);
    }

    // ============ SETTLEMENT ============

    function settle() external phaseSettlement preventReentrant {
        require(!_SETTLED_, "ALREADY_SETTLED");
        _SETTLED_ = true;

        (uint256 poolBase, uint256 poolQuote, uint256 ownerQuote) = getSettleResult();
        _UNUSED_QUOTE_ = _QUOTE_TOKEN_.balanceOf(address(this)).sub(poolQuote).sub(ownerQuote);
        _UNUSED_BASE_ = _BASE_TOKEN_.balanceOf(address(this)).sub(poolBase);
        uint256 avgPrice = DecimalMath.divCeil(poolQuote.add(ownerQuote), _UNUSED_BASE_);

        // 这里的目的是让开盘价尽量等于avgPrice
        // 我们统一设定k=1，如果quote和base不平衡，就必然要截断一边
        // DVM截断了quote，所以如果进入池子的quote很多，就要把quote设置成DVM的base
        // m = avgPrice
        // i = m (1-quote/(m*base))
        // if quote = m*base i = 1
        // if quote > m*base reverse
        uint256 baseDepth = DecimalMath.mulFloor(avgPrice, poolBase);
        if (poolQuote == baseDepth) {
            _POOL_ = IDVMFactory(_POOL_FACTORY_).createDODOVendingMachine(
                address(this),
                address(_BASE_TOKEN_),
                address(_QUOTE_TOKEN_),
                3e15,
                0,
                1,
                DecimalMath.ONE
            );
        } else if (poolQuote < baseDepth) {
            uint256 ratio = DecimalMath.ONE.sub(DecimalMath.divFloor(poolQuote, baseDepth));
            _POOL_ = IDVMFactory(_POOL_FACTORY_).createDODOVendingMachine(
                address(this),
                address(_BASE_TOKEN_),
                address(_QUOTE_TOKEN_),
                3e15,
                0,
                avgPrice.mul(ratio).mul(ratio).divCeil(DecimalMath.ONE2),
                DecimalMath.ONE
            );
        } else if (poolQuote > baseDepth) {
            uint256 ratio = DecimalMath.ONE.sub(DecimalMath.divFloor(baseDepth, poolQuote));
            _POOL_ = IDVMFactory(_POOL_FACTORY_).createDODOVendingMachine(
                address(this),
                address(_QUOTE_TOKEN_),
                address(_BASE_TOKEN_),
                3e15,
                0,
                DecimalMath.reciprocalFloor(avgPrice).mul(ratio).mul(ratio).divCeil(
                    DecimalMath.ONE2
                ),
                DecimalMath.ONE
            );
        }

        _transferBaseOut(_POOL_, poolBase);
        _transferQuoteOut(_POOL_, poolQuote);
        _transferQuoteOut(_OWNER_, ownerQuote);

        IDVM(_POOL_).buyShares(address(this));
    }

    // in case something wrong with base token contract
    function emergencySettle() external phaseSettlement preventReentrant {
        require(!_SETTLED_, "ALREADY_SETTLED");
        require(
            block.timestamp > _PHASE_CALM_ENDTIME_.add(_SETTLEMENT_EXPIRED_TIME_),
            "NOT_EMERGENCY"
        );
        _SETTLED_ = true;
        _UNUSED_QUOTE_ = _QUOTE_TOKEN_.balanceOf(address(this));
        _UNUSED_BASE_ = _BASE_TOKEN_.balanceOf(address(this));
    }

    // ============ Pricing ============

    function getSettleResult()
        public
        view
        returns (
            uint256 poolBase,
            uint256 poolQuote,
            uint256 ownerQuote
        )
    {
        poolQuote = _QUOTE_TOKEN_.balanceOf(address(this));
        if (poolQuote > _POOL_QUOTE_CAP_) {
            poolQuote = _POOL_QUOTE_CAP_;
        }
        (uint256 soldBase, ) = PMMPricing.sellQuoteToken(_getPMMState(), poolQuote);
        poolBase = _TOTAL_BASE_.sub(soldBase);
        if (poolBase < _POOL_BASE_RESERVE_) {
            poolBase = _POOL_BASE_RESERVE_;
        }
        ownerQuote = DecimalMath.mulFloor(poolQuote, _OWNER_QUOTE_RATIO_);
        poolQuote = poolQuote.sub(ownerQuote);
    }

    function _getPMMState() internal view returns (PMMPricing.PMMState memory state) {
        state.i = _I_;
        state.K = _K_;
        state.B = _TOTAL_BASE_;
        state.Q = 0;
        state.B0 = state.B;
        state.Q0 = 0;
        state.R = PMMPricing.RState.ONE;
    }

    // ============ Asset In ============

    function _getQuoteInput() internal view returns (uint256 input) {
        return _QUOTE_TOKEN_.balanceOf(address(this)).sub(_QUOTE_RESERVE_);
    }

    // ============ Set States ============

    function _sync() internal {
        uint256 quoteBalance = _QUOTE_TOKEN_.balanceOf(address(this));
        if (quoteBalance != _QUOTE_RESERVE_) {
            _QUOTE_RESERVE_ = quoteBalance;
        }
    }

    // ============ Asset Out ============

    function _transferBaseOut(address to, uint256 amount) internal {
        if (amount > 0) {
            _BASE_TOKEN_.safeTransfer(to, amount);
        }
    }

    function _transferQuoteOut(address to, uint256 amount) internal {
        if (amount > 0) {
            _QUOTE_TOKEN_.safeTransfer(to, amount);
        }
    }
}
