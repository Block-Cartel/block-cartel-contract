// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./libraries/Address.sol";

import "./interfaces/IERC20.sol";

contract StakingWarmup {
    using Address for address;

    address public immutable staking;
    address public immutable sBLOCKS;

    constructor ( address _staking, address _sBLOCKS ) {
        require( _staking != address(0) );
        staking = _staking;
        require( _sBLOCKS != address(0) );
        sBLOCKS = _sBLOCKS;
    }

    function retrieve( address _staker, uint256 _amount ) external {
        require( msg.sender == staking );
        IERC20( sBLOCKS ).transfer( _staker, _amount );
    }
}