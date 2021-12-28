// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./interfaces/IERC20.sol";

import "./libraries/SafeMath.sol";

import "./types/Ownable.sol";

contract aBLOCKSMigration is Ownable {
    using SafeMath for uint256;

    uint256 swapEndBlock;

    IERC20 public BLOCKS; 
    IERC20 public aBLOCKS; 

    bool public isInitialized;

    mapping(address => uint256) public senderInfo;

    modifier onlyInitialized() {
        require(isInitialized, "not initialized");
        _;
    }

    function initialize(
        address _BLOCKS,
        address _aBLOCKS,
        uint256 _swapDuration
    ) public onlyOwner() {
        BLOCKS = IERC20(_BLOCKS);
        aBLOCKS = IERC20(_aBLOCKS);
        swapEndBlock = block.number.add(_swapDuration);
        isInitialized = true;
    }

    function migrate(
        uint256 amount
    ) external onlyInitialized() {
        require(
            aBLOCKS.balanceOf(msg.sender) >= amount,
            "amount above user balance"
        );
        require(block.number < swapEndBlock, "swapping of aBLOCKS has ended");

        aBLOCKS.transferFrom(msg.sender, address(this), amount);
        senderInfo[msg.sender] = senderInfo[msg.sender].add(amount);
        BLOCKS.transfer(msg.sender, amount);
    }

    function reclaim() external {
        require(senderInfo[msg.sender] > 0, "user has no aBLOCKS to withdraw");
        require(
            block.timestamp > swapEndBlock,
            "aBLOCKS swap is still ongoing"
        );

        uint256 amount = senderInfo[msg.sender];
        senderInfo[msg.sender] = 0;
        aBLOCKS.transfer(msg.sender, amount);
    }

    function withdraw() external onlyOwner() {
        require(block.number > swapEndBlock, "swapping of aBLOCKS has not ended");
        uint256 amount = BLOCKS.balanceOf(address(this));

        BLOCKS.transfer(msg.sender, amount);
    }
}