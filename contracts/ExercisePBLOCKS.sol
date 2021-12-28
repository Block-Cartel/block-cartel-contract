// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IPBLOCKS.sol";
import "./interfaces/IBLOCKSCirculatingSupply.sol";

/**
 *  Exercise contract for unapproved sellers prior to migrating pBLOCKS.
 *  It is not possible for a user to use both (no double dipping).
 */

contract ExercisepBLOCKS {
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    
    address owner;
    address newOwner;
    
    address immutable pBLOCKS;
    address immutable BLOCKS;
    address immutable DAI;
    address immutable treasury;
    address immutable circulatingBLOCKSContract;
    
    struct Term {
        uint percent; // 4 decimals ( 5000 = 0.5% )
        uint claimed;
        uint max;
    }
    mapping( address => Term ) public terms;
    
    mapping( address => address ) public walletChange;
    
    constructor( address _pBLOCKS, address _BLOCKS, address _dai, address _treasury, address _circulatingBLOCKSContract ) {
        owner = msg.sender;
        require( _pBLOCKS != address(0) );
        pBLOCKS = _pBLOCKS;
        require( _BLOCKS != address(0) );
        BLOCKS = _BLOCKS;
        require( _dai != address(0) );
        DAI = _dai;
        require( _treasury != address(0) );
        treasury = _treasury;
        require( _circulatingBLOCKSContract != address(0) );
        circulatingBLOCKSContract = _circulatingBLOCKSContract;
    }
    
    // Sets terms for a new wallet
    function setTerms(address _vester, uint _rate, uint _claimed, uint _max ) external {
        require( msg.sender == owner, "Sender is not owner" );
        require( _max >= terms[ _vester ].max, "cannot lower amount claimable" );
        require( _rate >= terms[ _vester ].percent, "cannot lower vesting rate" );
        require( _claimed >= terms[ _vester ].claimed, "cannot lower claimed" );
        // require( !IPBLOCKS( pBLOCKS ).isApprovedSeller( _vester ), "reverted isApplovedSeller" );
        require( IPBLOCKS( pBLOCKS ).isApprovedSeller( _vester ), "reverted isApplovedSeller" );

        terms[ _vester ] = Term({
            percent: _rate,
            claimed: _claimed,
            max: _max
        });
    }

    // Allows wallet to redeem pBLOCKS for BLOCKS
    function exercise( uint _amount ) external {
        Term memory info = terms[ msg.sender ];
        if (msg.sender != owner) {
            require( redeemable( info ) >= _amount, "Not enough vested" );
        }
        require( info.max.sub( info.claimed ) >= _amount, "Claimed over max" );

        IERC20( DAI ).safeTransferFrom( msg.sender, address(this), _amount );
        IERC20( pBLOCKS ).safeTransferFrom( msg.sender, address(this), _amount );
        
        IERC20( DAI ).approve( treasury, _amount );
        uint BLOCKSToSend = ITreasury( treasury ).deposit( _amount, DAI, 0 );

        terms[ msg.sender ].claimed = info.claimed.add( _amount );

        IERC20( BLOCKS ).safeTransfer( msg.sender, BLOCKSToSend );
    }
    
    // Allows wallet owner to transfer rights to a new address
    function pushWalletChange( address _newWallet ) external {
        require( terms[ msg.sender ].percent != 0 );
        walletChange[ msg.sender ] = _newWallet;
    }
    
    // Allows wallet to pull rights from an old address
    function pullWalletChange( address _oldWallet ) external {
        require( walletChange[ _oldWallet ] == msg.sender, "wallet did not push" );
        
        walletChange[ _oldWallet ] = address(0);
        terms[ msg.sender ] = terms[ _oldWallet ];
        delete terms[ _oldWallet ];
    }

    // Amount a wallet can redeem based on current supply
    function redeemableFor( address _vester ) public view returns (uint) {
        return redeemable( terms[ _vester ]);
    }
    
    function redeemable( Term memory _info ) internal view returns ( uint ) {
        return ( IBLOCKSCirculatingSupply( circulatingBLOCKSContract ).circulatingSupply().mul( _info.percent ).mul( 1000 ) ).sub( _info.claimed );
    }

    function pushOwnership( address _newOwner ) external returns ( bool ) {
        require( msg.sender == owner, "Sender is not owner" );
        require( _newOwner != address(0) );
        newOwner = _newOwner;
        return true;
    }
    
    function pullOwnership() external returns ( bool ) {
        require( msg.sender == newOwner );
        owner = newOwner;
        newOwner = address(0);
        return true;
    }
}