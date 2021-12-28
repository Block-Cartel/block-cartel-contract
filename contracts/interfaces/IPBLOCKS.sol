// SPDX-License-Identifier: AGPL-3.0-or-later\
pragma solidity ^0.7.5;

interface IPBLOCKS {
    function isApprovedSeller(address _account) external returns (bool);
    function burnFrom( address account_, uint256 amount_ ) external;
}