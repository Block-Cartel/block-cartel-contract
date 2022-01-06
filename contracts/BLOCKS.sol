// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IBLOCKS.sol";
import "./interfaces/IERC20Permit.sol";
import "./types/Ownable.sol"
import "./types/ERC20Permit.sol";
import "./types/BLOCKSAccessControlled.sol";

contract BLOCKS is IERC20, ERC20Permit, IBLOCKS, BLOCKSAccessControlled {

    using SafeMath for uint256;
    using Address for address;
    address public team_address;
    uint256 public deploy_time;
    uint256 private transferedAmount;
    address public nftContract;
    address public treasury;
    
    modifier checkWithdrwalAddressTime(address userAddress, uint256 amount) {
        if(userAddress != team_address){
            _;
        }
        else{
           if(block.timestamp > deploy_time + 4 weeks && block.timestamp < deploy_time + 52 weeks){
               require(transferedAmount + amount < 20000000000000, "Address 20% withdrawal time hasn't reached.");
               _;
           }
           else if(block.timestamp > deploy_time + 52 weeks){
               _;
           }
           else{
               revert("Address all withdrawal time hasn't reached.");
           }
        }
    }
    
    constructor(address _authority, address _team_address)
    ERC20("BLOCKS", "BLOCKS", 9)
    ERC20Permit("BLOCKS")
    BLOCKSAccessControlled(IBLOCKSAuthority(_authority))
    {
        _balances[msg.sender] = 100000000000000;
        _totalSupply = 100000000000000; //100K
        team_address = _team_address;
        deploy_time = block.timestamp;

    }

    function setNFTContract (
        address _address
    ) external onlyOwner() returns ( bool ) {
        nftContract = _address;
        return true;
    }

    function setTreasury (
        address _address
    ) external onlyOwner() returns ( bool ) {
        treasury = _address;
        return true;
    }

    function mint(
        address account_,
        uint256 amount_
    ) external override {
        if (msg.sender == treasury || msg.sender == nftContract)
            _mint(account_, amount_);
        else revert("Un authorized");
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
        uint256 decreasedAllowance_ = allowance(account_, msg.sender).sub(amount_, "ERC20: burn amount exceeds allowance");
        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override checkWithdrwalAddressTime(msg.sender, amount){
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

}