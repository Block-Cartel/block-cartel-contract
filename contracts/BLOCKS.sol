// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";

import "./interfaces/IBLOCKS.sol";
import "./interfaces/IERC20Permit.sol";

import "./types/ERC20Permit.sol";
import "./types/BLOCKSAccessControlled.sol";

contract BLOCKS is ERC20Permit, IBLOCKS, BLOCKSAccessControlled {

    using SafeMath for uint256;
    using Address for address;

    constructor(address _authority)
    ERC20("BLOCKS", "BLOCKS", 9)
    ERC20Permit("BLOCKS")
    BLOCKSAccessControlled(IBLOCKSAuthority(_authority)) {
        _balances[msg.sender] = 1000000000000000; // 1000000
        _totalSupply = 1000000000000000;
    }

    function mint(
        address account_,
        uint256 amount_
    ) external override onlyVault {
        _mint(account_, amount_);
    }

    function burn(
        uint256 amount
    ) external override {
        _burn(msg.sender, amount);
    }

    function burnFrom(
        address account_,
        uint256 amount_
    ) external override {
        _burnFrom(account_, amount_);
    }

    function _burnFrom(
        address account_,
        uint256 amount_
    ) internal {
        uint256 decreasedAllowance_ =
            allowance(account_, msg.sender).sub(
                amount_,
                "ERC20: burn amount exceeds allowance"
            );

        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }
}