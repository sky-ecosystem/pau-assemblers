// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Vm } from "../../lib/forge-std/src/Vm.sol";

import { UnitTestBase, IAccessControlReader } from "./UnitTestBase.t.sol";

import { PAUAdministeredAgentFactory } from "../../src/PAUAdministeredAgentFactory.sol";

import {
    IPAUFactoryLike,
    IAdministeredAgentFactoryLike
} from "../../src/PAUAdministeredAgentFactory.sol";

import { IPAUAdministeredAgentFactory } from "../../src/interfaces/IPAUAdministeredAgentFactory.sol";

import { MockPAUFactory, MockController } from "../mocks/Mocks.sol";

import { AdministeredAgentFactory } from "../../lib/pau-administered-agent/src/AdministeredAgentFactory.sol";
import { IAdministeredAgent }        from "../../lib/pau-administered-agent/src/interfaces/IAdministeredAgent.sol";

abstract contract PAUAdministeredAgentFactory_TestBase is UnitTestBase {

    struct Deployed {
        IAccessControlReader accessControls;
        MockController       controller;
        IAccessControlReader proxy;
        IAccessControlReader rateLimits;
        IAdministeredAgent   agent;
    }

    MockPAUFactory              internal pauFactory;
    AdministeredAgentFactory    internal agentFactory;
    PAUAdministeredAgentFactory internal factory;

    function setUp() public virtual {
        pauFactory   = new MockPAUFactory();
        agentFactory = new AdministeredAgentFactory();

        vm.prank(deployer);
        factory = new PAUAdministeredAgentFactory(
            IPAUFactoryLike(address(pauFactory)),
            IAdministeredAgentFactoryLike(address(agentFactory))
        );
    }

    /// @dev Convenience wrapper for a standard deploy with no role-admin config.
    function _deploy(
        address admin_,
        bytes32[] memory ids,
        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig,
        IPAUAdministeredAgentFactory.AdministeredAgentConfig memory agentConfig
    )
        internal
        returns (Deployed memory d)
    {
        return _deployStandard(admin_, ids, adminConfig, agentConfig, _emptyRoleAdminConfig());
    }

    function _deployStandard(
        address admin_,
        bytes32[] memory ids,
        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig,
        IPAUAdministeredAgentFactory.AdministeredAgentConfig memory agentConfig,
        IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig[] memory roleAdminConfig
    )
        internal
        returns (Deployed memory d)
    {
        (
            address ac,
            address ctrl,
            address px,
            address rl,
            address ag
        ) = factory.deploy(admin_, ids, adminConfig, agentConfig, roleAdminConfig);

        return _wrap(ac, ctrl, px, rl, ag);
    }

    function _deployFreezable(
        address admin_,
        address[] memory freezers,
        bytes32[] memory ids,
        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig,
        IPAUAdministeredAgentFactory.AdministeredAgentConfig memory agentConfig,
        IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig[] memory roleAdminConfig
    )
        internal
        returns (Deployed memory d)
    {
        (
            address ac,
            address ctrl,
            address px,
            address rl,
            address ag
        ) = factory.deployFreezable(admin_, freezers, ids, adminConfig, agentConfig, roleAdminConfig);

        return _wrap(ac, ctrl, px, rl, ag);
    }

    function _wrap(
        address ac,
        address ctrl,
        address px,
        address rl,
        address ag
    )
        private
        pure
        returns (Deployed memory d)
    {
        d.accessControls = IAccessControlReader(ac);
        d.controller     = MockController(ctrl);
        d.proxy          = IAccessControlReader(px);
        d.rateLimits     = IAccessControlReader(rl);
        d.agent          = IAdministeredAgent(ag);
    }

    /// @dev `n` globally-unique, non-zero addresses starting at index `start`.
    function _slice(uint256 start, uint256 n) internal pure returns (address[] memory out) {
        out = new address[](n);
        for (uint256 i = 0; i < n; ++i) {
            out[i] = _addr(start + i);
        }
    }

}

contract PAUAdministeredAgentFactory_Constructor_Tests is PAUAdministeredAgentFactory_TestBase {

    function test_initialState() external view {
        assertEq(address(factory.pauFactory()),               address(pauFactory));
        assertEq(address(factory.administeredAgentFactory()), address(agentFactory));
        assertEq(factory.VERSION(),                           "1.0.0");
        assertEq(factory.ALLOCATOR_ROLE(),                    ALLOCATOR_ROLE);
    }

    function test_constructor_zeroPAUFactory() external {
        vm.expectRevert(IPAUAdministeredAgentFactory.ZeroPAUFactory.selector);
        new PAUAdministeredAgentFactory(
            IPAUFactoryLike(address(0)),
            IAdministeredAgentFactoryLike(address(agentFactory))
        );
    }

    function test_constructor_zeroAdministeredAgentFactory() external {
        vm.expectRevert(IPAUAdministeredAgentFactory.ZeroAdministeredAgentFactory.selector);
        new PAUAdministeredAgentFactory(
            IPAUFactoryLike(address(pauFactory)),
            IAdministeredAgentFactoryLike(address(0))
        );
    }

}

contract PAUAdministeredAgentFactory_Deploy_Tests is PAUAdministeredAgentFactory_TestBase {

    function test_deploy_minimal_rolesAndRenounce() external {
        bytes32[] memory ids = _oneIntegration();

        Deployed memory d = _deploy(admin, ids, _emptyAdminConfig(), _emptyAgentConfig());

        // Controller role wired on proxy + rate limits.
        assertTrue(d.proxy.hasRole(CONTROLLER_ROLE,      address(d.controller)));
        assertTrue(d.rateLimits.hasRole(CONTROLLER_ROLE, address(d.controller)));

        // Primary admin received DEFAULT_ADMIN_ROLE across the stack.
        assertTrue(d.proxy.hasRole(DEFAULT_ADMIN_ROLE,          admin));
        assertTrue(d.rateLimits.hasRole(DEFAULT_ADMIN_ROLE,     admin));
        assertTrue(d.accessControls.hasRole(DEFAULT_ADMIN_ROLE, admin));

        // Agent is the allocator and `admin` is its admin.
        assertTrue(d.accessControls.hasRole(ALLOCATOR_ROLE, address(d.agent)));
        assertTrue(d.agent.getIsAdmin(admin));
        assertEq(d.agent.adminCount(), 1);

        // Integrations forwarded verbatim.
        assertEq(d.controller.updateIntegrationsCallCount(), 1);
        assertEq(d.controller.lastIds(),                     ids);

        // Factory renounced every privileged role it held during bootstrap.
        assertFalse(d.proxy.hasRole(DEFAULT_ADMIN_ROLE,          address(factory)));
        assertFalse(d.rateLimits.hasRole(DEFAULT_ADMIN_ROLE,     address(factory)));
        assertFalse(d.accessControls.hasRole(DEFAULT_ADMIN_ROLE, address(factory)));
        assertFalse(d.agent.getIsAdmin(address(factory)));
    }

    function test_deploy_withFullConfig() external {
        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig =
            IPAUAdministeredAgentFactory.AdminConfig({
                controllerAdmins:        _slice(1,  2),
                proxyAdmins:             _slice(10, 2),
                rateLimitsAdmins:        _slice(20, 2),
                administeredAgentAdmins: _slice(30, 2)
            });

        IPAUAdministeredAgentFactory.AdministeredAgentConfig memory agentConfig =
            IPAUAdministeredAgentFactory.AdministeredAgentConfig({
                ids:      _oneIntegration(),
                actors:   _slice(40, 3),
                grantors: _slice(50, 3),
                revokers: _slice(60, 3)
            });

        Deployed memory d = _deploy(admin, _oneIntegration(), adminConfig, agentConfig);

        _assertAdminConfig(d, adminConfig);
        _assertAgentConfig(d, agentConfig, adminConfig);
    }

    function _assertAdminConfig(
        Deployed memory d,
        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig
    )
        internal
        view
    {
        for (uint256 i = 0; i < adminConfig.proxyAdmins.length; ++i) {
            assertTrue(d.proxy.hasRole(DEFAULT_ADMIN_ROLE, adminConfig.proxyAdmins[i]));
        }
        for (uint256 i = 0; i < adminConfig.rateLimitsAdmins.length; ++i) {
            assertTrue(d.rateLimits.hasRole(DEFAULT_ADMIN_ROLE, adminConfig.rateLimitsAdmins[i]));
        }
        for (uint256 i = 0; i < adminConfig.controllerAdmins.length; ++i) {
            assertTrue(d.accessControls.hasRole(DEFAULT_ADMIN_ROLE, adminConfig.controllerAdmins[i]));
        }
    }

    function _assertAgentConfig(
        Deployed memory d,
        IPAUAdministeredAgentFactory.AdministeredAgentConfig memory agentConfig,
        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig
    )
        internal
        view
    {
        for (uint256 i = 0; i < agentConfig.actors.length; ++i) {
            assertTrue(d.agent.getIsActor(agentConfig.actors[i]));
        }
        for (uint256 i = 0; i < agentConfig.grantors.length; ++i) {
            assertTrue(d.agent.getIsGrantor(agentConfig.grantors[i]));
        }
        for (uint256 i = 0; i < agentConfig.revokers.length; ++i) {
            assertTrue(d.agent.getIsRevoker(agentConfig.revokers[i]));
        }
        for (uint256 i = 0; i < adminConfig.administeredAgentAdmins.length; ++i) {
            assertTrue(d.agent.getIsAdmin(adminConfig.administeredAgentAdmins[i]));
        }

        assertEq(d.agent.actorCount(),   agentConfig.actors.length);
        assertEq(d.agent.grantorCount(), agentConfig.grantors.length);
        assertEq(d.agent.revokerCount(), agentConfig.revokers.length);
        // primary admin + extra agent admins, factory renounced.
        assertEq(d.agent.adminCount(), adminConfig.administeredAgentAdmins.length + 1);
        assertFalse(d.agent.getIsAdmin(address(factory)));
    }

    function test_deploy_emitsEvent() external {
        bytes32[] memory ids = _oneIntegration();

        vm.recordLogs();
        _deploy(admin, ids, _emptyAdminConfig(), _emptyAgentConfig());
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 factoryLogs = 0;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(factory)) continue;
            ++factoryLogs;
            // admin is the only indexed parameter.
            assertEq(logs[i].topics[1], bytes32(uint256(uint160(admin))));
        }
        assertEq(factoryLogs, 1);
    }

    /**********************************************************************************************/
    /*** Revert / gap cases                                                                     ***/
    /**********************************************************************************************/

    // Empty integrations: the factory skips the Controller.updateIntegrations call entirely.
    function test_deploy_emptyIntegrations_skipsUpdate() external {
        Deployed memory d = _deploy(admin, new bytes32[](0), _emptyAdminConfig(), _emptyAgentConfig());

        assertEq(d.controller.updateIntegrationsCallCount(), 0);
        // Stack is still fully wired and the factory still renounced.
        assertTrue(d.proxy.hasRole(CONTROLLER_ROLE, address(d.controller)));
        assertTrue(d.agent.getIsAdmin(admin));
        assertFalse(d.accessControls.hasRole(DEFAULT_ADMIN_ROLE, address(factory)));
    }

    function test_deploy_zeroAdmin() external {
        vm.expectRevert(IPAUAdministeredAgentFactory.ZeroAdmin.selector);
        _deploy(address(0), _oneIntegration(), _emptyAdminConfig(), _emptyAgentConfig());
    }

    // GAP: duplicate actors abort the entire deploy (AdministeredAgent rejects re-adds).
    function test_deploy_duplicateActor() external {
        address dup = _addr(99);
        address[] memory actors = new address[](2);
        actors[0] = dup;
        actors[1] = dup;

        IPAUAdministeredAgentFactory.AdministeredAgentConfig memory agentConfig = _emptyAgentConfig();
        agentConfig.actors = actors;

        vm.expectRevert(abi.encodeWithSelector(IAdministeredAgent.AlreadyActor.selector, dup));
        _deploy(admin, _oneIntegration(), _emptyAdminConfig(), agentConfig);
    }

    // GAP: passing `admin` again inside administeredAgentAdmins aborts the deploy.
    function test_deploy_adminDuplicatedAsAgentAdmin() external {
        address[] memory agentAdmins = new address[](1);
        agentAdmins[0] = admin;

        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig = _emptyAdminConfig();
        adminConfig.administeredAgentAdmins = agentAdmins;

        vm.expectRevert(abi.encodeWithSelector(IAdministeredAgent.AlreadyAdmin.selector, admin));
        _deploy(admin, _oneIntegration(), adminConfig, _emptyAgentConfig());
    }

    function test_deploy_duplicateGrantor() external {
        address dup = _addr(123);
        address[] memory grantors = new address[](2);
        grantors[0] = dup;
        grantors[1] = dup;

        IPAUAdministeredAgentFactory.AdministeredAgentConfig memory agentConfig = _emptyAgentConfig();
        agentConfig.grantors = grantors;

        vm.expectRevert(abi.encodeWithSelector(IAdministeredAgent.AlreadyGrantor.selector, dup));
        _deploy(admin, _oneIntegration(), _emptyAdminConfig(), agentConfig);
    }

    /**********************************************************************************************/
    /*** Freezable proxy + role-admin config                                                    ***/
    /**********************************************************************************************/

    function test_deploy_standardProxy_grantsControllerRole() external {
        Deployed memory d = _deploy(admin, _oneIntegration(), _emptyAdminConfig(), _emptyAgentConfig());

        assertFalse(pauFactory.lastProxyFreezable());
        assertTrue(d.proxy.hasRole(CONTROLLER_ROLE,  address(d.controller)));
        assertFalse(d.proxy.hasRole(ALLOCATOR_ROLE,  address(d.controller)));
    }

    function test_deployFreezable_grantsAllocatorRoleAndFreezers() external {
        address[] memory freezers = _slice(70, 2);

        Deployed memory d = _deployFreezable(
            admin, freezers, _oneIntegration(), _emptyAdminConfig(), _emptyAgentConfig(), _emptyRoleAdminConfig()
        );

        // Freezable variant deployed and gated on ALLOCATOR_ROLE rather than CONTROLLER.
        assertTrue(pauFactory.lastProxyFreezable());
        assertTrue(d.proxy.hasRole(ALLOCATOR_ROLE,   address(d.controller)));
        assertFalse(d.proxy.hasRole(CONTROLLER_ROLE, address(d.controller)));

        // Freezers were granted FREEZER_ROLE on the proxy.
        assertTrue(d.proxy.hasRole(FREEZER_ROLE, freezers[0]));
        assertTrue(d.proxy.hasRole(FREEZER_ROLE, freezers[1]));

        // RateLimits always uses CONTROLLER, and the rest of the wiring is unchanged.
        assertTrue(d.rateLimits.hasRole(CONTROLLER_ROLE, address(d.controller)));
        assertTrue(d.proxy.hasRole(DEFAULT_ADMIN_ROLE,   admin));
        assertFalse(d.proxy.hasRole(DEFAULT_ADMIN_ROLE,  address(factory)));
    }

    function test_deployFreezable_noFreezers() external {
        Deployed memory d = _deployFreezable(
            admin, new address[](0), _oneIntegration(), _emptyAdminConfig(), _emptyAgentConfig(), _emptyRoleAdminConfig()
        );

        assertTrue(pauFactory.lastProxyFreezable());
        assertTrue(d.proxy.hasRole(ALLOCATOR_ROLE, address(d.controller)));
    }

    function test_deploy_roleAdminConfig_appliesSetRoleAdmin() external {
        bytes32 role      = keccak256("CUSTOM_ROLE");
        bytes32 roleAdmin = keccak256("CUSTOM_ROLE_ADMIN");

        IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig[] memory cfg =
            new IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig[](1);
        cfg[0] = IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig({
            role:      role,
            adminRole: roleAdmin
        });

        Deployed memory d = _deployStandard(
            admin, _oneIntegration(), _emptyAdminConfig(), _emptyAgentConfig(), cfg
        );

        assertEq(d.accessControls.getRoleAdmin(role), roleAdmin);
    }

    /**********************************************************************************************/
    /*** Fuzz                                                                                    ***/
    /**********************************************************************************************/

    function testFuzz_deploy_agentMembership(
        uint8 nActors,
        uint8 nGrantors,
        uint8 nRevokers,
        uint8 nAdmins
    )
        external
    {
        nActors   = uint8(bound(nActors,   0, 5));
        nGrantors = uint8(bound(nGrantors, 0, 5));
        nRevokers = uint8(bound(nRevokers, 0, 5));
        nAdmins   = uint8(bound(nAdmins,   0, 5));

        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig = _emptyAdminConfig();
        adminConfig.administeredAgentAdmins = _slice(1000, nAdmins);

        IPAUAdministeredAgentFactory.AdministeredAgentConfig memory agentConfig =
            IPAUAdministeredAgentFactory.AdministeredAgentConfig({
                ids:      _oneIntegration(),
                actors:   _slice(2000, nActors),
                grantors: _slice(3000, nGrantors),
                revokers: _slice(4000, nRevokers)
            });

        Deployed memory d = _deploy(admin, _oneIntegration(), adminConfig, agentConfig);

        assertEq(d.agent.actorCount(),   nActors);
        assertEq(d.agent.grantorCount(), nGrantors);
        assertEq(d.agent.revokerCount(), nRevokers);
        // admin + extra agent admins, minus the factory which renounced.
        assertEq(d.agent.adminCount(),   uint256(nAdmins) + 1);

        assertTrue(d.agent.getIsAdmin(admin));
        assertFalse(d.agent.getIsAdmin(address(factory)));

        _assertAgentConfig(d, agentConfig, adminConfig);
    }

    function testFuzz_deploy_adminConfigRoles(uint8 nProxy, uint8 nRate, uint8 nCtrl) external {
        nProxy = uint8(bound(nProxy, 0, 6));
        nRate  = uint8(bound(nRate,  0, 6));
        nCtrl  = uint8(bound(nCtrl,  0, 6));

        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig =
            IPAUAdministeredAgentFactory.AdminConfig({
                controllerAdmins:        _slice(5000, nCtrl),
                proxyAdmins:             _slice(6000, nProxy),
                rateLimitsAdmins:        _slice(7000, nRate),
                administeredAgentAdmins: new address[](0)
            });

        Deployed memory d = _deploy(admin, _oneIntegration(), adminConfig, _emptyAgentConfig());

        _assertAdminConfig(d, adminConfig);
    }

    function testFuzz_deploy_forwardsIntegrationIds(bytes32[] memory ids) external {
        vm.assume(ids.length > 0 && ids.length <= 10);

        Deployed memory d = _deploy(admin, ids, _emptyAdminConfig(), _emptyAgentConfig());

        assertEq(d.controller.lastIds(), ids);
    }

}
