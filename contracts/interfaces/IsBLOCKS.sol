// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./IERC20.sol";

interface IsBLOCKS is IERC20 {
    function rebase(
        uint256 BLOCKSProfit_,
        uint256 epoch_
    ) external returns (uint256);

    function circulatingSupply() external view returns (uint256);

    function balanceOf(
        address who
    ) external view override returns (uint);

    function getdebtBalances(
        address who
    ) external view returns (uint256);

    function gonsForBalance(
        uint256 amount
    ) external view returns ( uint256 );

    function balanceForGons(
        uint256 gons
    ) external view returns ( uint256 );
    
    function index() external view returns ( uint256 );

    // function toG(uint amount) external view returns (uint);

    // function fromG(uint amount) external view returns (uint);

     function changeDebt(
        uint256 amount,
        address debtor,
        bool add
    ) external;

    function debtBalances(address _address) external view returns (uint256);

}