/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;

import {IERC20} from "../intf/IERC20.sol";
import {UniversalERC20} from "./lib/UniversalERC20.sol";
import {SafeMath} from "../lib/SafeMath.sol";
import {IDODOV1} from "./intf/IDODOV1.sol";
import {IDODOSellHelper} from "./helper/DODOSellHelper.sol";
import {IWETH} from "../intf/IWETH.sol";
import {IDODOApprove} from "../intf/IDODOApprove.sol";
import {IDODOV1Proxy01} from "./intf/IDODOV1Proxy01.sol";
import {ReentrancyGuard} from "../lib/ReentrancyGuard.sol";

contract DODOV1Proxy01 is IDODOV1Proxy01, ReentrancyGuard {
    using SafeMath for uint256;
    using UniversalERC20 for IERC20;

    // ============ Storage ============

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public dodoApprove;
    address public dodoSellHelper;
    address payable public _WETH_;

    // ============ Events ============

    event OrderHistory(
        address indexed fromToken,
        address indexed toToken,
        address indexed sender,
        uint256 fromAmount,
        uint256 returnAmount
    );

    // ============ Modifiers ============

    modifier judgeExpired(uint256 deadline) {
        require(deadline >= block.timestamp, "DODOV1Proxy01: EXPIRED");
        _;
    }

    constructor(
        address _dodoApprove,
        address _dodoSellHelper,
        address payable _weth
    ) public {
        dodoApprove = _dodoApprove;
        dodoSellHelper = _dodoSellHelper;
        _WETH_ = _weth;
    }

    fallback() external payable {}

    receive() external payable {}

    function dodoSwap(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        address[] memory dodoPairs,
        uint8[] memory directions,
        uint256 deadline
    ) external virtual override payable judgeExpired(deadline) returns (uint256 returnAmount) {
        if (fromToken != ETH_ADDRESS) {
            IDODOApprove(dodoApprove).claimTokens(
                fromToken,
                msg.sender,
                address(this),
                fromTokenAmount
            );
        } else {
            require(msg.value == fromTokenAmount, "DODOV1Proxy01: ETH_AMOUNT_NOT_MATCH");
            IWETH(_WETH_).deposit{value: fromTokenAmount}();
        }

        for (uint256 i = 0; i < dodoPairs.length; i++) {
            address curDodoPair = dodoPairs[i];
            if (directions[i] == 0) {
                address curDodoBase = IDODOV1(curDodoPair)._BASE_TOKEN_();
                uint256 curAmountIn = IERC20(curDodoBase).balanceOf(address(this));
                IERC20(curDodoBase).universalApproveMax(curDodoPair, curAmountIn);
                IDODOV1(curDodoPair).sellBaseToken(curAmountIn, 0, "");
            } else {
                address curDodoQuote = IDODOV1(curDodoPair)._QUOTE_TOKEN_();
                uint256 curAmountIn = IERC20(curDodoQuote).balanceOf(address(this));
                IERC20(curDodoQuote).universalApproveMax(curDodoPair, curAmountIn);
                uint256 canBuyBaseAmount = IDODOSellHelper(dodoSellHelper).querySellQuoteToken(
                    curDodoPair,
                    curAmountIn
                );
                IDODOV1(curDodoPair).buyBaseToken(canBuyBaseAmount, curAmountIn, "");
            }
        }

        returnAmount = IERC20(toToken).universalBalanceOf(address(this));
        require(returnAmount >= minReturnAmount, "DODOV1Proxy01: Return amount is not enough");

        if (toToken == ETH_ADDRESS) IWETH(_WETH_).withdraw(returnAmount);
        IERC20(toToken).universalTransfer(msg.sender, returnAmount);

        emit OrderHistory(fromToken, toToken, msg.sender, fromTokenAmount, returnAmount);
    }

    function externalSwap(
        address fromToken,
        address toToken,
        address approveTarget,
        address to,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        bytes memory callDataConcat,
        uint256 deadline
    ) external virtual override payable judgeExpired(deadline) returns (uint256 returnAmount) {
        uint256 toTokenOriginBalance = IERC20(toToken).universalBalanceOf(msg.sender);

        if (fromToken != ETH_ADDRESS) {
            IDODOApprove(dodoApprove).claimTokens(
                fromToken,
                msg.sender,
                address(this),
                fromTokenAmount
            );
            IERC20(fromToken).universalApproveMax(approveTarget, fromTokenAmount);
        }

        (bool success, ) = to.call{value: fromToken == ETH_ADDRESS ? msg.value : 0}(callDataConcat);

        require(success, "DODOV1Proxy01: Contract Swap execution Failed");

        IERC20(fromToken).universalTransfer(
            msg.sender,
            IERC20(fromToken).universalBalanceOf(address(this))
        );

        IERC20(toToken).universalTransfer(
            msg.sender,
            IERC20(toToken).universalBalanceOf(address(this))
        );
        returnAmount = IERC20(toToken).universalBalanceOf(msg.sender).sub(toTokenOriginBalance);
        require(returnAmount >= minReturnAmount, "DODOV1Proxy01: Return amount is not enough");

        emit OrderHistory(fromToken, toToken, msg.sender, fromTokenAmount, returnAmount);
    }
}
