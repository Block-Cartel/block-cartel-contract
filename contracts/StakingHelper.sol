// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./libraries/Address.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IStaking.sol";

contract StakingHelper {
    using Address for address;

    address public immutable staking;
    address public immutable BLOCKS;

    constructor(
        address _staking,
        address _BLOCKS
    ) {
        require(_staking != address(0));
        staking = _staking;
        require(_BLOCKS != address(0));
        BLOCKS = _BLOCKS;
    }

    function stake(
        uint256 _amount,
        address recipient
    ) external {
        IERC20(BLOCKS).transferFrom(msg.sender, address(this), _amount);
        IERC20(BLOCKS).approve(staking, _amount);
        IStaking(staking).stake(recipient, _amount);
        IStaking(staking).claim(recipient, true);
    }
}