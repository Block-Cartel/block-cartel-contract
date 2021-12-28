// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

interface ITaxHelperV2 {
    function calcTotalTax(uint256 _amount, address _to, uint256 _epoch_number, uint256 isEntry) external returns ( uint256 );

    function removeTaxTracker(address _to) external;

    function processEntityTax() external;
}