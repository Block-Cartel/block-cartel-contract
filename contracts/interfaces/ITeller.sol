// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

interface ITeller {
    function newBond( 
        address _bonder, 
        address _principal,
        uint256 _principalPaid,
        uint256 _payout, 
        uint256 _expires,
        address _feo
    ) external returns ( uint256 index_ );
    function redeemAll(address _bonder) external returns (uint256);
    function redeemOne(address _bonder, address _principal) external returns (uint256);
    function redeem(address _bonder, uint256[] memory _indexes) external returns (uint256);
    function getReward() external;
    function setFEReward(uint256 reward) external;
    function updateIndexesForAll(address _bonder) external;
    function updateIndexesForOne(address _bonder, address _principal) external;
    function pendingFor(address _bonder, uint256 _index) external view returns (uint256);
    function claimablePendingFor(address _bonder, uint256 _index) external view returns (uint256);
    function pendingForIndexes(address _bonder, uint256[] memory _indexes) external view returns (uint256 pending_);
    function totalPendingFor(address _bonder, address _principal) external view returns (uint256 pending_);
    function totalClaimablePendingFor(address _bonder, address _principal) external view returns (uint256 pending_);
    function percentVestedFor(address _bonder, uint256 _index) external view returns (uint256 percentVested_);
}