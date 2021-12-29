// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

/**
 * Staking
 */

import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/Address.sol";

import "./interfaces/IBLOCKS.sol";
import "./interfaces/IsBLOCKS.sol";
import "./interfaces/IDistributor.sol";
import "./interfaces/IWarmup.sol";

import "./types/BLOCKSAccessControlled.sol";


contract BLOCKSStaking is BLOCKSAccessControlled {

    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IBLOCKS;
    using SafeERC20 for IsBLOCKS;

    /* ========== EVENTS ========== */

    event DistributorSet(address distributor);
    event WarmupSet(uint256 warmup);

    /* ========== DATA STRUCTURES ========== */

    struct Epoch {
        uint256 length;
        uint256 number;
        uint256 endBlock;
        uint256 distribute;
    }

    struct Claim {
        uint256 deposit;
        uint256 gons;
        uint256 expiry;
        bool lock; // prevents malicious delays for claim
    }

    /* ========== STATE VARIABLES ========== */

    IBLOCKS public immutable BLOCKS;
    IsBLOCKS public immutable sBLOCKS;

    address private distributor;

    Epoch public epoch;

    mapping(address => Claim) public warmupInfo;
    uint256 public warmupPeriod;
    address private warmupContract;

    mapping(address => uint256) public stakingTimeTrack;

    /* ========== CONSTRUCTOR ========== */

    constructor ( 
        address _BLOCKS, 
        address _sBLOCKS,
        uint256 _epochLength,
        uint256 _firstEpochNumber,
        uint256 _firstEpochBlock,
        address _authority
    ) BLOCKSAccessControlled(IBLOCKSAuthority(_authority)) {
        require( _BLOCKS != address(0), "Zero address: BLOCKS" );
        BLOCKS = IBLOCKS( _BLOCKS );
        require( _sBLOCKS != address(0), "Zero address: sBLOCKS" );
        sBLOCKS = IsBLOCKS( _sBLOCKS );

        epoch = Epoch({
            length: _epochLength,
            number: _firstEpochNumber,
            endBlock: _firstEpochBlock,
            distribute: 0
        });
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice stake BLOCKS to enter warmup
     * @param _amount uint
     * @param _to address
     * @return uint
     */
    function stake(
        address _to,
        uint256 _amount
    ) external returns ( uint256 ) {
        rebase();

        BLOCKS.safeTransferFrom( msg.sender, address(this), _amount );

        Claim memory info = warmupInfo[_to];
        require( !info.lock, "Deposits for account are locked" );

        warmupInfo[_to] = Claim({
            deposit: info.deposit.add(_amount),
            gons: info.gons.add(sBLOCKS.gonsForBalance(_amount)),
            expiry: epoch.number.add(warmupPeriod),
            lock: info.lock
        });

        sBLOCKS.safeTransfer( warmupContract, _amount );

        return _amount;
    }

    /**
     * @notice retrieve stake from warmup
     * @param _to address
     * @param _rebasing bool
     * @return uint
     */
    function claim (
        address _to,
        bool _rebasing
    ) public returns ( uint256 ) {
        Claim memory info = warmupInfo[ _to ];

        if ( epoch.number >= info.expiry && info.expiry != 0 ) {
            delete warmupInfo[ _to ];

            return _send( _to, sBLOCKS.balanceForGons(info.gons), _rebasing );
        }
        return 0;
    }

    /**
     * @notice forfeit stake and retrieve BLOCKS
     * @return uint
     */
    function forfeit() external returns (uint256) {
        Claim memory info = warmupInfo[msg.sender];
        delete warmupInfo[msg.sender];

        IWarmup( warmupContract ).retrieve( address(this), sBLOCKS.balanceForGons( info.gons ) );
        BLOCKS.safeTransfer( msg.sender, info.deposit );

        return info.deposit;
    }

    /**
     * @notice prevent new deposits or claims from ext. address (protection from malicious activity)
     */
    function toggleLock() external {
        warmupInfo[ msg.sender ].lock = !warmupInfo[ msg.sender ].lock;
    }

    /**
     * @notice redeem sBLOCKS for BLOCKS
     * @param _to address
     * @param _amount uint
     * @param _trigger bool
     * @param _rebasing bool
     * @return amount_ uint
     */
    function unstake(
        address _to,
        uint256 _amount,
        bool _trigger,
        bool _rebasing
    ) external returns (uint256 amount_) {
        if (_trigger) {
            rebase();
        }

        uint256 amount = _amount;
        if ( _rebasing ) {
            sBLOCKS.safeTransferFrom( msg.sender, address(this), _amount );
        } else {
        }

        BLOCKS.safeTransfer( _to, _amount );

        return amount;
    }

    /**
        @notice trigger rebase if epoch over
     */
    function rebase() public {
        if(epoch.endBlock <= block.number) {
            sBLOCKS.rebase( epoch.distribute, epoch.number );

            epoch.endBlock = epoch.endBlock.add(epoch.length);
            epoch.number++;

            if ( distributor != address(0) ) {
                IDistributor( distributor ).distribute();
            }

            if( contractBalance() <= totalStaked() ) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = contractBalance().sub( totalStaked() );
            }
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice send staker their amount as sBLOCKS
     * @param _to address
     * @param _amount uint
     * @param _rebasing bool
     */
    function _send(
        address _to,
        uint256 _amount,
        bool _rebasing
    ) internal returns ( uint256 ) {
        if ( _rebasing ) {
            IWarmup( warmupContract ).retrieve( _to, _amount );
            return _amount;
        } else {
            return _amount;
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
        @notice returns the sBLOCKS index, which tracks rebase growth
        @return uint
     */
    function index() public view returns ( uint256 ) {
        return sBLOCKS.index();
    }

    /**
        @notice returns contract BLOCKS holdings, including bonuses provided
        @return uint
     */
    function contractBalance() public view returns ( uint256 ) {
        return BLOCKS.balanceOf( address(this) );
    }

    /**
     * @notice total supply staked
     */
    function totalStaked() public view returns ( uint256 ) {
        return sBLOCKS.circulatingSupply();
    }

    /**
     * @notice total supply in warmup
     */
    function supplyInWarmup() public view returns ( uint256 ) {
        return sBLOCKS.balanceOf( warmupContract );
    }

    /* ========== MANAGERIAL FUNCTIONS ========== */

    enum CONTRACTS { DISTRIBUTOR, WARMUP }

    /**
        @notice sets the contract address for LP staking
        @param _contract address
     */
    function setContract( CONTRACTS _contract, address _address ) external onlyGovernor() {
        if( _contract == CONTRACTS.DISTRIBUTOR ) { // 0
            distributor = _address;
            emit DistributorSet(_address);
        } else if ( _contract == CONTRACTS.WARMUP ) { // 1
            require( warmupContract == address( 0 ), "Warmup cannot be set more than once" );
            warmupContract = _address;
        } 
    }

    /**
     * @notice set warmup period for new stakers
     * @param _warmupPeriod uint
     */
    function setWarmupLength(uint256 _warmupPeriod) external onlyGovernor {
        warmupPeriod = _warmupPeriod;
        emit WarmupSet(_warmupPeriod);
    }
}