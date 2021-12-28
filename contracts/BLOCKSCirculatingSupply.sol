// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./libraries/SafeMath.sol";

import "./interfaces/IERC20.sol";

contract BLOCKSCirculatingSupply {
    using SafeMath for uint;

    bool public isInitialized;

    address public BLOCKS;
    address public owner;
    address[] public nonCirculatingBLOCKSAddresses;

    constructor( address _owner ) {        
        owner = _owner;
    }

    function initialize( address _BLOCKS ) external returns ( bool ) {
        require( msg.sender == owner, "caller is not owner" );
        require( isInitialized == false );

        BLOCKS = _BLOCKS;

        isInitialized = true;

        return true;
    }

    function circulatingSupply() external view returns ( uint ) {
        uint _totalSupply = IERC20( BLOCKS ).totalSupply();

        uint _circulatingSupply = _totalSupply.sub(getNonCirculatingBLOCKS());

        return _circulatingSupply;
    }

    function getNonCirculatingBLOCKS() public view returns ( uint ) {
        uint _nonCirculatingBLOCKS;

        for( uint i=0; i < nonCirculatingBLOCKSAddresses.length; i = i.add( 1 ) ) {
            _nonCirculatingBLOCKS = _nonCirculatingBLOCKS.add( IERC20( BLOCKS ).balanceOf( nonCirculatingBLOCKSAddresses[i] ) );
        }

        return _nonCirculatingBLOCKS;
    }

    function setNonCirculatingBLOCKSAddresses( address[] calldata _nonCirculatingAddresses ) external returns ( bool ) {
        require( msg.sender == owner, "Sender is not owner" );
        nonCirculatingBLOCKSAddresses = _nonCirculatingAddresses;

        return true;
    }

    function transferOwnership( address _owner ) external returns ( bool ) {
        require( msg.sender == owner, "Sender is not owner" );

        owner = _owner;

        return true;
    }
}