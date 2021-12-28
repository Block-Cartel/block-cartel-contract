// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./interfaces/IERC20.sol";
import "./interfaces/IsBLOCKS.sol";

import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";

import "./types/ERC20.sol";

contract wsBLOCKS is ERC20 {
    using SafeERC20 for ERC20;
    using Address for address;
    using SafeMath for uint;

    address public immutable sBLOCKS;

    constructor( address _sBLOCKS ) ERC20( "Wrapped sBLOCKS", "wsBLOCKS", 18 ) {
        require( _sBLOCKS != address(0) );
        sBLOCKS = _sBLOCKS;
    }

    /**
        @notice wrap sBLOCKS
        @param _amount uint
        @return uint
     */
    function wrap( uint256 _amount ) external returns ( uint256 ) {
        IERC20( sBLOCKS ).transferFrom( msg.sender, address(this), _amount );

        uint256 value = sBLOCKSTowBLOCKS( _amount );
        _mint( msg.sender, value );
        return value;
    }

    /**
        @notice unwrap sBLOCKS
        @param _amount uint
        @return uint
     */
    function unwrap( uint256 _amount ) external returns ( uint256 ) {
        _burn( msg.sender, _amount );

        uint256 value = wBLOCKSTosBLOCKS( _amount );
        IERC20( sBLOCKS ).transfer( msg.sender, value );
        return value;
    }

    /**
        @notice converts wBLOCKS amount to sBLOCKS
        @param _amount uint
        @return uint
     */
    function wBLOCKSTosBLOCKS( uint256 _amount ) public view returns ( uint256 ) {
        return _amount.mul( IsBLOCKS( sBLOCKS ).index() ).div( 10 ** decimals() );
    }

    /**
        @notice converts sBLOCKS amount to wBLOCKS
        @param _amount uint
        @return uint
     */
    function sBLOCKSTowBLOCKS( uint256 _amount ) public view returns ( uint256 ) {
        return _amount.mul( 10 ** decimals() ).div( IsBLOCKS( sBLOCKS ).index() );
    }

}
