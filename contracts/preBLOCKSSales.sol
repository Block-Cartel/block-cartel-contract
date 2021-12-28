// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./interfaces/IERC20.sol";

import "./libraries/SafeMath.sol";
import "./libraries/Context.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";

import "./types/Ownable.sol";

contract PreBLOCKSSales is Ownable {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  event SaleStarted( address indexed activator, uint256 timestamp );
  event SaleEnded( address indexed activator, uint256 timestamp );
  event SellerApproval( address indexed approver, address indexed seller, string indexed message );

  IERC20 public dai;

  IERC20 public pBLOCKS;

  address private _saleProceedsAddress;

  uint256 public pBLOCKSPrice;

  bool public initialized;

  mapping( address => bool ) public approvedBuyers;

  constructor() {}

  function initialize( 
    address pBLOCKS_, 
    address dai_,
    uint256 pBLOCKSPrice_,
    address saleProceedsAddress_
  ) external onlyOwner {
    require( !initialized );
    pBLOCKS = IERC20( pBLOCKS_ );
    dai = IERC20( dai_ );
    pBLOCKSPrice = pBLOCKSPrice_;
    _saleProceedsAddress = saleProceedsAddress_;
    initialized = true;
  }

  function setPBLOCKSPrice( uint256 newPBLOCKSPrice_ ) external onlyOwner() returns ( uint256 ) {
    pBLOCKSPrice = newPBLOCKSPrice_;
    return pBLOCKSPrice;
  }

  function _approveBuyer( address newBuyer_ ) internal onlyOwner() returns ( bool ) {
    approvedBuyers[newBuyer_] = true;
    return approvedBuyers[newBuyer_];
  }

  function approveBuyer( address newBuyer_ ) external onlyOwner() returns ( bool ) {
    return _approveBuyer( newBuyer_ );
  }

  function approveBuyers( address[] calldata newBuyers_ ) external onlyOwner() returns ( uint256 ) {
    for( uint256 iteration_ = 0; newBuyers_.length > iteration_; iteration_++ ) {
      _approveBuyer( newBuyers_[iteration_] );
    }
    return newBuyers_.length;
  }

  function _calculateAmountPurchased( uint256 amountPaid_ ) internal view returns ( uint256 ) {
    return amountPaid_.mul( pBLOCKSPrice ) / 100;
  }

  function buyPBLOCKS( uint256 amountPaid_ ) external returns ( bool ) {
    require( approvedBuyers[msg.sender], "Buyer not approved." );
    uint256 pBLOCKSAmountPurchased_ = _calculateAmountPurchased( amountPaid_ );
    dai.safeTransferFrom( msg.sender, address(this), amountPaid_ );
    require(pBLOCKS.balanceOf(address(this)) > pBLOCKSAmountPurchased_, "reasdfaweraer");
    // dai.safeTransfer( _saleProceedsAddress, amountPaid_ );
    pBLOCKS.transfer( msg.sender, pBLOCKSAmountPurchased_ );
    return true;
  }

  function withdrawTokens( address tokenToWithdraw_ ) external onlyOwner() returns ( bool ) {
    IERC20( tokenToWithdraw_ ).safeTransfer( msg.sender, IERC20( tokenToWithdraw_ ).balanceOf( address( this ) ) );
    return true;
  }
}