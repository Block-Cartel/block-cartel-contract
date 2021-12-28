// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IStakingHelper.sol";
import "./interfaces/IsBLOCKS.sol";
import "./interfaces/ITeller.sol";

import "./types/BLOCKSAccessControlled.sol";

contract BondTeller is ITeller, BLOCKSAccessControlled {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IsBLOCKS;
    using Address for address;

    /* ========== EVENTS =========== */

    event Redeemed(address indexed bonder, uint256 payout);

    /* ========== MODIFIERS ========== */

    modifier onlyDepository() {
        require(msg.sender == depository, "Only depository");
        _;
    }

    /* ========== STRUCTS ========== */

    // Info for bond holder
    struct Bond {
        address principal; // token used to pay for bond
        uint256 principalPaid; // amount of principal token paid for bond
        uint256 payout; // sBLOCKS remaining to be paid. agnostic balance
        uint256 vested; // Block when bond is vested
        uint256 created; // time bond was created
        uint256 redeemed; // time bond was redeemed
    }

    /* ========== STATE VARIABLES ========== */

    address internal immutable depository; // contract where users deposit bonds
    IStakingHelper internal immutable stakingHelper; // contract to stake payout
    ITreasury internal immutable treasury;
    IERC20 internal immutable BLOCKS;
    IsBLOCKS internal immutable sBLOCKS; // payment token

    mapping(address => Bond[]) public bonderInfo; // user data
    mapping(address => uint256[]) public indexesFor; // user bond indexes

    mapping(address => uint256) public FERs; // front end operator rewards
    uint256 public feReward = 0;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _depository,
        address _stakingHelper,
        address _treasury,
        address _BLOCKS,
        address _sBLOCKS,
        address _authority
    ) BLOCKSAccessControlled(IBLOCKSAuthority(_authority)) {
        require(_depository != address(0), "Zero address: Depository");
        depository = _depository;
        require(_stakingHelper != address(0), "Zero address: Staking");
        stakingHelper = IStakingHelper(_stakingHelper);
        require(_treasury != address(0), "Zero address: Treasury");
        treasury = ITreasury(_treasury);
        require(_BLOCKS != address(0), "Zero address: BLOCKS");
        BLOCKS = IERC20(_BLOCKS);
        require(_sBLOCKS != address(0), "Zero address: sBLOCKS");
        sBLOCKS = IsBLOCKS(_sBLOCKS);
    }

    /* ========== DEPOSITORY FUNCTIONS ========== */

    /**
     * @notice add new bond payout to user data
     * @param _bonder address
     * @param _principal address
     * @param _principalPaid uint256
     * @param _payout uint256
     * @param _expires uint256
     * @param _feo address
     * @return index_ uint256
     */
    function newBond(
        address _bonder,
        address _principal,
        uint256 _principalPaid,
        uint256 _payout,
        uint256 _expires,
        address _feo
    ) external override onlyDepository returns (uint256 index_) {
        uint256 reward = _payout.mul(feReward).div(10000);
        treasury.mint(address(this), _payout.add(reward));

        BLOCKS.approve(address(stakingHelper), _payout);
        stakingHelper.stake(_payout, address(this), false);

        FERs[_feo] = FERs[_feo].add(reward); // front end operator reward

        index_ = bonderInfo[_bonder].length;

        // store bond & stake payout
        bonderInfo[_bonder].push(
            Bond({
                principal: _principal,
                principalPaid: _principalPaid,
                // payout: sBLOCKS.toG(_payout),
                payout: _payout,
                vested: _expires,
                created: block.timestamp,
                redeemed: 0
            })
        );
    }

    /* ========== INTERACTABLE FUNCTIONS ========== */

    /**
     *  @notice redeems all redeemable bonds
     *  @param _bonder address
     *  @return uint256
     */
    function redeemAll(address _bonder) external override returns (uint256) {
        updateIndexesForAll(_bonder);
        return redeem(_bonder, indexesFor[_bonder]);
    }

    /**
     *  @notice redeems redeemable bond
     *  @param _bonder address
     *  @return uint256
     */
    function redeemOne(address _bonder, address principal) external override returns (uint256) {
        updateIndexesForOne(_bonder, principal);
        return redeem(_bonder, indexesFor[_bonder]);
    }

    /**
     *  @notice redeem bond for user
     *  @param _bonder address
     *  @param _indexes calldata uint256[]
     *  @return uint256
     */
    function redeem(address _bonder, uint256[] memory _indexes) public override returns (uint256) {
        uint256 dues;
        for (uint256 i = 0; i < _indexes.length; i++) {
            Bond memory info = bonderInfo[_bonder][_indexes[i]];

            if (claimablePendingFor(_bonder, _indexes[i]) != 0) {
                bonderInfo[_bonder][_indexes[i]].redeemed = block.timestamp; // mark as redeemed

                dues = dues.add(info.payout);
            }
        }

        // dues = sBLOCKS.fromG(dues);
        dues = dues;

        emit Redeemed(_bonder, dues);
        pay(_bonder, dues);
        return dues;
    }

    // pay reward to front end operator
    function getReward() external override {
        uint256 reward = FERs[msg.sender];
        FERs[msg.sender] = 0;
        BLOCKS.safeTransfer(msg.sender, reward);
    }

    /* ========== OWNABLE FUNCTIONS ========== */

    // set reward for front end operator (4 decimals. 100 = 1%)
    function setFEReward(uint256 reward) external override onlyPolicy {
        feReward = reward;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     *  @notice send payout
     *  @param _amount uint256
     */
    function pay(address _bonder, uint256 _amount) internal {
        sBLOCKS.safeTransfer(_bonder, _amount);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     *  @notice returns indexes of live bonds
     *  @param _bonder address
     */
    function updateIndexesForAll(address _bonder) public override {
        Bond[] memory info = bonderInfo[_bonder];
        delete indexesFor[_bonder];
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].redeemed == 0) {
                indexesFor[_bonder].push(i);
            }
        }
    }

    /**
     *  @notice returns indexes of live bonds
     *  @param _bonder address
     */
    function updateIndexesForOne(address _bonder, address _principal) public override {
        Bond[] memory info = bonderInfo[_bonder];
        delete indexesFor[_bonder];
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].redeemed == 0 && info[i].principal == _principal) {
                indexesFor[_bonder].push(i);
            }
        }
    }

    // PAYOUT

    /**
     * @notice calculate amount of BLOCKS available for claim for single bond
     * @param _bonder address
     * @param _index uint256
     * @return uint256
     */
    function claimablePendingFor(address _bonder, uint256 _index) public view override returns (uint256) {
        if (bonderInfo[_bonder][_index].redeemed == 0 && bonderInfo[_bonder][_index].vested <= block.number) {
            return bonderInfo[_bonder][_index].payout;
        }
        return 0;
    }
    
    function pendingFor(address _bonder, uint256 _index) public view override returns (uint256) {
        if (bonderInfo[_bonder][_index].redeemed == 0) {
            return bonderInfo[_bonder][_index].payout;
        }
        return 0;
    }

    /**
     * @notice calculate amount of BLOCKS available for claim for array of bonds
     * @param _bonder address
     * @param _indexes uint256[]
     * @return pending_ uint256
     */
    function pendingForIndexes(address _bonder, uint256[] memory _indexes) public view override returns (uint256 pending_) {
        for (uint256 i = 0; i < _indexes.length; i++) {
            pending_ = pending_.add(pendingFor(_bonder, i));
        }
        // pending_ = sBLOCKS.fromG(pending_);
        pending_ = pending_;
    }

    /**
     *  @notice total pending on all bonds for bonder
     *  @param _bonder address
     *  @return pending_ uint256
     */
    function totalClaimablePendingFor(address _bonder, address _principal) public view override returns (uint256 pending_) {
        Bond[] memory info = bonderInfo[_bonder];
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].principal == _principal) {
                pending_ = pending_.add(claimablePendingFor(_bonder, i));
            }
        }
        // pending_ = sBLOCKS.fromG(pending_);
        pending_ = pending_;
    }

    /**
     *  @notice total pending on all bonds for bonder
     *  @param _bonder address
     *  @return pending_ uint256
     */
    function totalPendingFor(address _bonder, address _principal) public view override returns (uint256 pending_) {
        Bond[] memory info = bonderInfo[_bonder];
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].principal == _principal) {
                pending_ = pending_.add(pendingFor(_bonder, i));
            }
        }
        // pending_ = sBLOCKS.fromG(pending_);
        pending_ = pending_;
    }

    // VESTING

    /**
     * @notice calculate how far into vesting a depositor is
     * @param _bonder address
     * @param _index uint256
     * @return percentVested_ uint256
     */
    function percentVestedFor(address _bonder, uint256 _index) public view override returns (uint256 percentVested_) {
        Bond memory bond = bonderInfo[_bonder][_index];

        uint256 timeSince = block.timestamp.sub(bond.created);
        uint256 term = bond.vested.sub(bond.created);

        percentVested_ = timeSince.mul(1e9).div(term);
    }
}
