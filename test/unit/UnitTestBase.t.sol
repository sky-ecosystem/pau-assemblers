// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IPAUAdministeredAgentFactory } from "../../src/interfaces/IPAUAdministeredAgentFactory.sol";

/// @notice Minimal role-reader used by tests to assert role state on the real
///         AccessControls / ALMProxy / RateLimits contracts without pulling in
///         their (payable) concrete types.
interface IAccessControlReader {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
}

abstract contract UnitTestBase is Test {

    /**********************************************************************************************/
    /*** Shared constants                                                                       ***/
    /**********************************************************************************************/

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant CONTROLLER_ROLE     = keccak256("CONTROLLER");
    bytes32 internal constant FREEZER_ROLE        = keccak256("FREEZER_ROLE");

    /**********************************************************************************************/
    /*** Shared actors                                                                          ***/
    /**********************************************************************************************/

    address internal admin        = makeAddr("admin");
    address internal deployer      = makeAddr("deployer");
    address internal unauthorized = makeAddr("unauthorized");

    /**********************************************************************************************/
    /*** Config builders                                                                        ***/
    /**********************************************************************************************/

    /// @dev Empty admin config (only the primary `admin` will receive roles).
    function _emptyAdminConfig()
        internal
        pure
        returns (IPAUAdministeredAgentFactory.AdminConfig memory config)
    {
        config = IPAUAdministeredAgentFactory.AdminConfig({
            accessControlAdmins:     new address[](0),
            proxyAdmins:             new address[](0),
            rateLimitsAdmins:        new address[](0),
            administeredAgentAdmins: new address[](0)
        });
    }

    /// @dev Agent config with no actors/grantors/revokers and the supplied integration ids.
    function _emptyAgentConfig()
        internal
        pure
        returns (IPAUAdministeredAgentFactory.AdministeredAgentConfig memory config)
    {
        config = IPAUAdministeredAgentFactory.AdministeredAgentConfig({
            actors:   new address[](0),
            grantors: new address[](0),
            revokers: new address[](0)
        });
    }

    /// @dev A single, non-empty integration id list (the Controller requires >= 1).
    function _oneIntegration() internal pure returns (bytes32[] memory ids) {
        ids    = new bytes32[](1);
        ids[0] = keccak256("INTEGRATION_0");
    }

    /// @dev Empty role-admin reconfiguration list.
    function _emptyRoleAdminConfig()
        internal
        pure
        returns (IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig[] memory config)
    {
        config = new IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig[](0);
    }

    /// @dev Deterministically derive a distinct, non-zero address from a seed.
    function _addr(uint256 seed) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode("addr", seed)))));
    }

    /// @dev Build an array of `n` distinct, non-zero addresses seeded by `salt`.
    function _addresses(uint256 n, uint256 salt) internal pure returns (address[] memory out) {
        out = new address[](n);
        for (uint256 i = 0; i < n; ++i) {
            out[i] = _addr(uint256(keccak256(abi.encode(salt, i))));
        }
    }

}
