// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "../types/BLOCKSAccessControlled.sol";

contract AccessControlledMock is BLOCKSAccessControlled {

    constructor( address _auth ) BLOCKSAccessControlled(IBLOCKSAuthority(_auth)) {}

    bool public governorOnlyTest;

    bool public guardianOnlyTest;

    bool public policyOnlyTest;

    bool public vaultOnlyTest;

    function governorTest() external onlyGovernor returns (bool) {
        governorOnlyTest = true;
        return governorOnlyTest;
    }

    function guardianTest() external onlyGuardian returns (bool) {
        guardianOnlyTest = true;
        return guardianOnlyTest;
    }
    
    function policyTest() external onlyPolicy returns (bool) {
        policyOnlyTest = true;
        return policyOnlyTest;
    }

    function vaultTest() external onlyVault returns (bool) {
        governorOnlyTest = true;
        return governorOnlyTest;
    }
}