/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

import {ReentrancyGuard} from "../lib/ReentrancyGuard.sol";
import {InitializableOwnable} from "../lib/InitializableOwnable.sol";

contract FeeRateModelLogic is ReentrancyGuard,InitializableOwnable {
    //DEFAULT
    uint256 public _FEE_RATE_;
    mapping(address => uint256) feeMapping;

    function setSpecificFeeRate(address trader, uint256 feeRate) external onlyOwner {
        require(trader != address(0), "INVALID ADDRESS!");
        feeMapping[trader] = feeRate;
    }

    function setFeeRate(uint256 newFeeRate) external onlyOwner {
       _FEE_RATE_ = newFeeRate;
    }
}
