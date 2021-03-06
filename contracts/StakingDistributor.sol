// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IDistributor.sol";

import "./types/BLOCKSAccessControlled.sol";


contract Distributor is IDistributor, BLOCKSAccessControlled {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    /* ====== VARIABLES ====== */

    IERC20 private immutable BLOCKS;
    ITreasury private immutable treasury;
    address private immutable staking;

    mapping(uint256 => Adjust) public adjustments;

    uint256 private immutable rateDenominator = 1000000;

    /* ====== STRUCTS ====== */

    struct Info {
        uint256 rate; // in ten-thousandths ( 5000 = 0.5% )
        address recipient;
    }
    Info[] public info;

    struct Adjust {
        bool add;
        uint256 rate;
        uint256 target;
    }

    /* ====== CONSTRUCTOR ====== */

    constructor(
        address _treasury,
        address _BLOCKS,
        address _staking, 
        address _authority
    ) BLOCKSAccessControlled(IBLOCKSAuthority(_authority)) {
        require(_treasury != address(0), "Zero address: Treasury");
        treasury = ITreasury(_treasury);
        require(_BLOCKS != address(0), "Zero address: BLOCKS");
        BLOCKS = IERC20(_BLOCKS);
        require(_staking != address(0), "Zero address: Staking");
        staking = _staking;
    }

    /* ====== PUBLIC FUNCTIONS ====== */

    /**
        @notice send epoch reward to staking contract
     */
    function distribute() external override {
        require(msg.sender == staking, "Only staking");

        // distribute rewards to each recipient
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].rate > 0) {
                treasury.mint(info[i].recipient, nextRewardAt(info[i].rate)); // mint and send from treasury
                adjust(i); // check for adjustment
            }
        }
    }

    /* ====== INTERNAL FUNCTIONS ====== */

    /**
        @notice increment reward rate for collector
     */
    function adjust(uint256 _index) internal {
        Adjust memory adjustment = adjustments[_index];
        if (adjustment.rate != 0) {
            if (adjustment.add) {
                // if rate should increase
                info[_index].rate = info[_index].rate.add(adjustment.rate); // raise rate
                if (info[_index].rate >= adjustment.target) {
                    // if target met
                    adjustments[_index].rate = 0; // turn off adjustment
                }
            } else {
                // if rate should decrease
                info[_index].rate = info[_index].rate.sub(adjustment.rate); // lower rate
                if (info[_index].rate <= adjustment.target) {
                    // if target met
                    adjustments[_index].rate = 0; // turn off adjustment
                }
            }
        }
    }

    /* ====== VIEW FUNCTIONS ====== */

    /**
        @notice view function for next reward at given rate
        @param _rate uint
        @return uint
     */
    function nextRewardAt(uint256 _rate) public view override returns (uint256) {
        return BLOCKS.totalSupply().mul(_rate).div(rateDenominator);
    }

    /**
        @notice view function for next reward for specified address
        @param _recipient address
        @return uint
     */
    function nextRewardFor(address _recipient) public view override returns (uint256) {
        uint256 reward;
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].recipient == _recipient) {
                reward = reward.add(nextRewardAt(info[i].rate));
            }
        }
        return reward;
    }

    /* ====== POLICY FUNCTIONS ====== */

    /**
        @notice adds recipient for distributions
        @param _recipient address
        @param _rewardRate uint
     */
    function addRecipient(address _recipient, uint256 _rewardRate) external override onlyGovernor {
        require(_recipient != address(0), "Zero address: Recipient");
        require(_rewardRate <= rateDenominator, "Rate cannot exceed denominator");
        info.push(Info({recipient: _recipient, rate: _rewardRate}));
    }

    /**
        @notice removes recipient for distributions
        @param _index uint
     */
    function removeRecipient(uint256 _index) external override {
        require(msg.sender == authority.governor() || msg.sender == authority.guardian(), "Caller is not governor or guardian");
        require(info[_index].recipient != address(0), "Recipient does not exist");
        info[_index].recipient = address(0);
        info[_index].rate = 0;
    }

    /**
        @notice set adjustment info for a collector's reward rate
        @param _index uint
        @param _add bool
        @param _rate uint
        @param _target uint
     */
    function setAdjustment(
        uint256 _index,
        bool _add,
        uint256 _rate,
        uint256 _target
    ) external override {
        require(msg.sender == authority.governor() || msg.sender == authority.guardian(), "Caller is not governor or guardian");
        require(info[_index].recipient != address(0), "Recipient does not exist");

        if (msg.sender == authority.guardian()) {
            require(_rate <= info[_index].rate.mul(25).div(1000), "Limiter: cannot adjust by >2.5%");
        }

        if (!_add) {
            require(_rate <= info[_index].rate, "Cannot decrease rate by more than it already is");
        }

        adjustments[_index] = Adjust({add: _add, rate: _rate, target: _target});
    }
}
