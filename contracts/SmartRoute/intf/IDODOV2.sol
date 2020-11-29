/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

interface IDODOV2 {

    //========== Common ==================

    function sellBase(address to) external returns (uint256 receiveQuoteAmount);

    function sellQuote(address to) external returns (uint256 receiveBaseAmount);

    function getVaultReserve() external view returns (uint256 baseReserve, uint256 quoteReserve);

    function _BASE_TOKEN_() external returns (address);

    function _QUOTE_TOKEN_() external returns (address);

    function _OWNER_() external returns (address);

    //========== DODOVendingMachine ========
    
    function createDODOVendingMachine(
        address creator,
        address baseToken,
        address quoteToken,
        uint256 lpFeeRate,
        uint256 mtFeeRate,
        uint256 i,
        uint256 k
    ) external returns (address newVendingMachine);

    // ============= permit =================
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    // ======================================

    function buyShares(address to) external returns (uint256,uint256,uint256);

    function sellShares(address to) external returns (uint256,uint256);

    //========== DODOPrivatePool ===========

    function createDODOPrivatePool() external returns (address newPrivatePool);

    function initDODOPrivatePool(
        address dppAddress,
        address creator,
        address baseToken,
        address quoteToken,
        uint256 lpFeeRate,
        uint256 mtFeeRate,
        uint256 k,
        uint256 i
    ) external;

    function reset(
        address operator,
        uint256 newLpFeeRate,
        uint256 newMtFeeRate,
        uint256 newI,
        uint256 newK,
        uint256 baseOutAmount,
        uint256 quoteOutAmount
    ) external; 


    //========== IDODOApprove  =============

    function claimTokens(address token,address who,address dest,uint256 amount) external;
    
    function getDODOProxy() external view returns (address);

}