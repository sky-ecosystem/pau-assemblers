// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { PAUAdministeredAgentFactory } from "../../src/PAUAdministeredAgentFactory.sol";

import {
    IPAUFactoryLike,
    IAdministeredAgentFactoryLike
} from "../../src/PAUAdministeredAgentFactory.sol";

import { IPAUAdministeredAgentFactory } from "../../src/interfaces/IPAUAdministeredAgentFactory.sol";

import { PAUFactory }               from "../../lib/diamond-pau/src/PAUFactory.sol";
import { AdministeredAgentFactory } from "../../lib/pau-administered-agent/src/AdministeredAgentFactory.sol";
import { IAdministeredAgent }        from "../../lib/pau-administered-agent/src/interfaces/IAdministeredAgent.sol";

interface IACL {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

/**
 * @notice Integration coverage against the *canonical* diamond-pau PAUFactory and the real
 *         AdministeredAgentFactory (no mocks). Exercises the adapter against the real bytecode.
 */
contract PAUAdministeredAgentFactory_Integration_Tests is Test {

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant CONTROLLER_ROLE    = keccak256("CONTROLLER");
    bytes32 internal constant ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant FREEZER_ROLE       = keccak256("FREEZER_ROLE");

    address internal beacon = makeAddr("beacon");
    address internal admin  = makeAddr("admin");

    PAUFactory                  internal pauFactory;
    AdministeredAgentFactory    internal agentFactory;
    PAUAdministeredAgentFactory internal factory;

    function setUp() external {
        pauFactory   = new PAUFactory(beacon);
        agentFactory = new AdministeredAgentFactory();

        factory = new PAUAdministeredAgentFactory(
            IPAUFactoryLike(address(pauFactory)),
            IAdministeredAgentFactoryLike(address(agentFactory))
        );
    }

    function _emptyAdminConfig()
        internal
        pure
        returns (IPAUAdministeredAgentFactory.AdminConfig memory c)
    {
        c = IPAUAdministeredAgentFactory.AdminConfig({
            controllerAdmins:        new address[](0),
            proxyAdmins:             new address[](0),
            rateLimitsAdmins:        new address[](0),
            administeredAgentAdmins: new address[](0)
        });
    }

    function _emptyAgentConfig()
        internal
        pure
        returns (IPAUAdministeredAgentFactory.AdministeredAgentConfig memory c)
    {
        c = IPAUAdministeredAgentFactory.AdministeredAgentConfig({
            actors:   new address[](0),
            grantors: new address[](0),
            revokers: new address[](0)
        });
    }

    function _emptyRoleAdminConfig()
        internal
        pure
        returns (IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig[] memory c)
    {
        c = new IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig[](0);
    }

    // End-to-end against the real PAU stack. With no integrations the Controller call is skipped,
    // so a full stack deploys and wires without needing a configured Beacon.
    function test_deploy_standardProxy_endToEnd() external {
        ( , address controller, address proxy, address rateLimits, address agent)
            = factory.deploy(
                admin,
                new bytes32[](0),
                _emptyAdminConfig(),
                _emptyAgentConfig(),
                _emptyRoleAdminConfig()
            );

        assertTrue(IACL(address(proxy)).hasRole(CONTROLLER_ROLE,      address(controller)));
        assertTrue(IACL(address(rateLimits)).hasRole(CONTROLLER_ROLE, address(controller)));
        assertTrue(IACL(address(proxy)).hasRole(DEFAULT_ADMIN_ROLE,   admin));

        assertTrue(IAdministeredAgent(address(agent)).getIsAdmin(admin));
        assertFalse(IAdministeredAgent(address(agent)).getIsAdmin(address(factory)));

        // Factory renounced its bootstrap roles.
        assertFalse(IACL(address(proxy)).hasRole(DEFAULT_ADMIN_ROLE,      address(factory)));
        assertFalse(IACL(address(rateLimits)).hasRole(DEFAULT_ADMIN_ROLE, address(factory)));
    }

    // The freezable variant deploys against the real factory and the Controller is granted
    // ALLOCATOR_ROLE (the role that gates the freezable proxy's doCall), not CONTROLLER. The
    // supplied freezer receives FREEZER_ROLE.
    function test_deployFreezable_endToEnd() external {
        address freezer = makeAddr("freezer");
        address[] memory freezers = new address[](1);
        freezers[0] = freezer;

        ( , address controller, address proxy, , )
            = factory.deployFreezable(
                admin,
                freezers,
                new bytes32[](0),
                _emptyAdminConfig(),
                _emptyAgentConfig(),
                _emptyRoleAdminConfig()
            );

        assertTrue(IACL(address(proxy)).hasRole(ALLOCATOR_ROLE,   address(controller)));
        assertFalse(IACL(address(proxy)).hasRole(CONTROLLER_ROLE, address(controller)));
        assertTrue(IACL(address(proxy)).hasRole(FREEZER_ROLE,     freezer));
        assertTrue(IACL(address(proxy)).hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

}
