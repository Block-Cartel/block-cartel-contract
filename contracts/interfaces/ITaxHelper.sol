// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

interface ITaxHelper {
    function calcTotalTax(uint256 _amount) external view returns ( uint256 );

    function processTax(uint256 _amount) external returns ( uint256 );

    function getRewardAmount(uint256 _deposit) external returns ( uint256 );
}