/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;

import {IERC20} from "../intf/IERC20.sol";
import {SafeERC20} from "../lib/SafeERC20.sol";
import {Ownable} from "../lib/Ownable.sol";

contract DODOApprove is Ownable {
    using SafeERC20 for IERC20;
    address public dodoProxy;

    // ============ Events ============

    event SetDODOProxy(address indexed oldProxy, address indexed newProxy);

    function setDODOProxy(address _dodoProxy) external onlyOwner {
        emit SetDODOProxy(dodoProxy, _dodoProxy);
        dodoProxy = _dodoProxy;
    }

    function getDODOProxy() public view returns (address) {
        return dodoProxy;
    }

    function claimTokens(
        address token,
        address who,
        address dest,
        uint256 amount
    ) external {
        require(msg.sender == dodoProxy, "DODOApprove:Access restricted");
        if (amount > 0) {
            IERC20(token).safeTransferFrom(who, dest, amount);
        }
    }
}
