// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IPAUAssembler } from "../../src/interfaces/IPAUAssembler.sol";

import { PAUAssembler } from "../../src/PAUAssembler.sol";

interface IAdministeredAgentLike {

    function actorCount() external view returns (uint256);

    function adminCount() external view returns (uint256);

    function getIsActor(address account) external view returns (bool);

    function getIsAdmin(address account) external view returns (bool);

    function getIsGrantor(address account) external view returns (bool);

    function getIsRevoker(address account) external view returns (bool);

    function grantorCount() external view returns (uint256);

    function revokerCount() external view returns (uint256);

}

interface IAccessControlLike {

    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    function hasRole(bytes32 role, address account) external view returns (bool);

}

interface IALMProxyLike {

    function CONTROLLER() external view returns (bytes32);

}

interface IControllerLike {

    struct Config {
        address facet;
        Wire[]  wires;
    }

    struct Integration {
        bytes32 id;
        Config  config;
    }

    struct Wire {
        bytes4 callSelector;
        bytes4 delegateSelector;
    }

    function accessControls() external view returns (address);

    function integrations() external view returns (Integration[] memory);

    function proxy() external view returns (address);

    function rateLimits() external view returns (address);

}

interface IRateLimitsLike {

    function CONTROLLER() external view returns (bytes32);

}

/**
 * @notice Integration coverage against the *canonical* diamond-pau PAUFactory and the real
 *         AdministeredAgentFactory (no mocks). Exercises the multi-stack assembler against the real
 *         bytecode: one shared ALMProxy, multiple AccessControls/RateLimits/Controllers cross
 *         referenced by id, and allocator agents wired to a referenced AccessControls.
 */
contract PAUAssembler_Integration_Tests is Test {

    address internal constant AAVE_FACET                 = 0x8CE890A96a193ff2DD4B2eA3C682326F655f6b62;
    address internal constant ADMINISTERED_AGENT_FACTORY = 0x2968c3b5478cF93B70aB1e24255d4EDBBd27a089;
    address internal constant PAU_FACTORY                = 0x69A5d548830AC2A4Ba90A44a2C75BDA71f97fc66;
    address internal constant TRANSFER_ASSET_FACET       = 0x4DA7608C331b8f135df5b985018933780eCd089D;

    bytes32 internal constant AAVE_INTEGRATION_ID           = "AAVE_FACET";
    bytes32 internal constant ALLOCATOR_ROLE                = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE            = 0x00;
    bytes32 internal constant TRANSFER_ASSET_INTEGRATION_ID = "TRANSFER_ASSET_FACET";

    bytes32 internal constant AC_A = "AC_A";
    bytes32 internal constant AC_B = "AC_B";
    bytes32 internal constant RL_A = "RL_A";
    bytes32 internal constant RL_B = "RL_B";

    PAUAssembler internal assembler;

    function setUp() external {
        vm.createSelectFork("mainnet", 25270600);

        assembler = new PAUAssembler(ADMINISTERED_AGENT_FACTORY, PAU_FACTORY);
    }

    /**********************************************************************************************/
    /*** Helpers                                                                                ***/
    /**********************************************************************************************/

    function _proxyConfig() internal returns (IPAUAssembler.ALMProxyConfig memory config) {
        config.admins    = new address[](1);
        config.admins[0] = makeAddr("proxyAdmin");
    }

    function _oneAdmin(bytes32 id, string memory label)
        internal
        returns (IPAUAssembler.AccessControlConfig memory config)
    {
        config.id        = id;
        config.admins    = new address[](1);
        config.admins[0] = makeAddr(label);
    }

    function _oneAdminRL(bytes32 id, string memory label)
        internal
        returns (IPAUAssembler.RateLimitConfig memory config)
    {
        config.id        = id;
        config.admins    = new address[](1);
        config.admins[0] = makeAddr(label);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroAdministeredAgentFactory() external {
        vm.expectRevert(IPAUAssembler.ZeroAdministeredAgentFactory.selector);
        new PAUAssembler(address(0), PAU_FACTORY);
    }

    function test_constructor_zeroPAUFactory() external {
        vm.expectRevert(IPAUAssembler.ZeroPAUFactory.selector);
        new PAUAssembler(ADMINISTERED_AGENT_FACTORY, address(0));
    }

    /**********************************************************************************************/
    /*** Initial State Test                                                                     ***/
    /**********************************************************************************************/

    function test_initialState() external view {
        assertEq(assembler.VERSION(),                  "1.0.0");
        assertEq(assembler.administeredAgentFactory(), ADMINISTERED_AGENT_FACTORY);
        assertEq(assembler.pauFactory(),               PAU_FACTORY);
    }

    /**********************************************************************************************/
    /*** deploy Revert Tests                                                                     ***/
    /**********************************************************************************************/

    function test_deploy_zeroProxyAdmin() external {
        IPAUAssembler.ALMProxyConfig memory proxyConfig;
        proxyConfig.admins = new address[](1); // [address(0)]

        vm.expectRevert(IPAUAssembler.ZeroDefaultAdmin.selector);
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitConfig[](0),
            new IPAUAssembler.AccessControlConfig[](0),
            new IPAUAssembler.AdministeredAgentConfig[](0),
            proxyConfig
        );
    }

    function test_deploy_noProxyAdmins() external {
        IPAUAssembler.ALMProxyConfig memory proxyConfig; // empty admins

        vm.expectRevert(IPAUAssembler.NoDefaultAdmins.selector);
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitConfig[](0),
            new IPAUAssembler.AccessControlConfig[](0),
            new IPAUAssembler.AdministeredAgentConfig[](0),
            proxyConfig
        );
    }

    function test_deploy_duplicateAccessControlsId() external {
        IPAUAssembler.AccessControlConfig[] memory acs = new IPAUAssembler.AccessControlConfig[](2);
        acs[0] = _oneAdmin(AC_A, "acAdmin0");
        acs[1] = _oneAdmin(AC_A, "acAdmin1");

        vm.expectRevert(abi.encodeWithSelector(IPAUAssembler.DuplicateAccessControlsId.selector, AC_A));
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitConfig[](0),
            acs,
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );
    }

    function test_deploy_duplicateRateLimitsId() external {
        IPAUAssembler.RateLimitConfig[] memory rls = new IPAUAssembler.RateLimitConfig[](2);
        rls[0] = _oneAdminRL(RL_A, "rlAdmin0");
        rls[1] = _oneAdminRL(RL_A, "rlAdmin1");

        vm.expectRevert(abi.encodeWithSelector(IPAUAssembler.DuplicateRateLimitsId.selector, RL_A));
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            rls,
            new IPAUAssembler.AccessControlConfig[](0),
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );
    }

    function test_deploy_invalidRateLimitsId() external {
        IPAUAssembler.AccessControlConfig[] memory acs = new IPAUAssembler.AccessControlConfig[](1);
        acs[0] = _oneAdmin(AC_A, "acAdmin0");

        IPAUAssembler.ControllerConfig[] memory ctrls = new IPAUAssembler.ControllerConfig[](1);
        ctrls[0] = IPAUAssembler.ControllerConfig({
            integrationIds  : new bytes32[](0),
            rateLimitId     : RL_A, // never deployed
            accessControlId : AC_A
        });

        vm.expectRevert(abi.encodeWithSelector(IPAUAssembler.InvalidRateLimitsId.selector, RL_A));
        assembler.deploy(
            ctrls,
            new IPAUAssembler.RateLimitConfig[](0),
            acs,
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );
    }

    function test_deploy_invalidAccessControlsId_controller() external {
        IPAUAssembler.RateLimitConfig[] memory rls = new IPAUAssembler.RateLimitConfig[](1);
        rls[0] = _oneAdminRL(RL_A, "rlAdmin0");

        IPAUAssembler.ControllerConfig[] memory ctrls = new IPAUAssembler.ControllerConfig[](1);
        ctrls[0] = IPAUAssembler.ControllerConfig({
            integrationIds  : new bytes32[](0),
            rateLimitId     : RL_A,
            accessControlId : AC_A // never deployed
        });

        vm.expectRevert(abi.encodeWithSelector(IPAUAssembler.InvalidAccessControlsId.selector, AC_A));
        assembler.deploy(
            ctrls,
            rls,
            new IPAUAssembler.AccessControlConfig[](0),
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );
    }

    function test_deploy_invalidAccessControlsId_agent() external {
        IPAUAssembler.AdministeredAgentConfig[] memory agents = new IPAUAssembler.AdministeredAgentConfig[](1);
        agents[0].accessControlId = AC_A; // never deployed
        agents[0].admins          = new address[](1);
        agents[0].admins[0]       = makeAddr("agentAdmin");

        vm.expectRevert(abi.encodeWithSelector(IPAUAssembler.InvalidAccessControlsId.selector, AC_A));
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitConfig[](0),
            new IPAUAssembler.AccessControlConfig[](0),
            agents,
            _proxyConfig()
        );
    }

    function test_deploy_noAgentAdmins() external {
        IPAUAssembler.AccessControlConfig[] memory acs = new IPAUAssembler.AccessControlConfig[](1);
        acs[0] = _oneAdmin(AC_A, "acAdmin0");

        IPAUAssembler.AdministeredAgentConfig[] memory agents = new IPAUAssembler.AdministeredAgentConfig[](1);
        agents[0].accessControlId = AC_A;
        // admins empty

        vm.expectRevert(IPAUAssembler.NoAgentAdmins.selector);
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitConfig[](0),
            acs,
            agents,
            _proxyConfig()
        );
    }

    function test_deploy_noAccessControlAdmins() external {
        IPAUAssembler.AccessControlConfig[] memory acs = new IPAUAssembler.AccessControlConfig[](1);
        acs[0].id = AC_A; // admins empty

        vm.expectRevert(IPAUAssembler.NoDefaultAdmins.selector);
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitConfig[](0),
            acs,
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );
    }

    /**********************************************************************************************/
    /*** deploy Happy Path                                                                       ***/
    /**********************************************************************************************/

    function test_deploy() external {
        // --- Build configs: 2 AccessControls, 2 RateLimits, 2 Controllers (one per pair), 1 agent.

        IPAUAssembler.AccessControlConfig[] memory acs = new IPAUAssembler.AccessControlConfig[](2);
        acs[0] = _oneAdmin(AC_A, "acAdminA");
        acs[1] = _oneAdmin(AC_B, "acAdminB");

        IPAUAssembler.RateLimitConfig[] memory rls = new IPAUAssembler.RateLimitConfig[](2);
        rls[0] = _oneAdminRL(RL_A, "rlAdminA");
        rls[1] = _oneAdminRL(RL_B, "rlAdminB");

        IPAUAssembler.ControllerConfig[] memory ctrls = new IPAUAssembler.ControllerConfig[](2);

        ctrls[0].integrationIds    = new bytes32[](1);
        ctrls[0].integrationIds[0] = AAVE_INTEGRATION_ID;
        ctrls[0].rateLimitId       = RL_A;
        ctrls[0].accessControlId   = AC_A;

        ctrls[1].integrationIds    = new bytes32[](1);
        ctrls[1].integrationIds[0] = TRANSFER_ASSET_INTEGRATION_ID;
        ctrls[1].rateLimitId       = RL_B;
        ctrls[1].accessControlId   = AC_B;

        IPAUAssembler.AdministeredAgentConfig[] memory agents = new IPAUAssembler.AdministeredAgentConfig[](1);
        agents[0].accessControlId = AC_A;
        agents[0].admins          = new address[](1);
        agents[0].admins[0]       = makeAddr("agentAdmin");
        agents[0].actors          = new address[](1);
        agents[0].actors[0]       = makeAddr("agentActor");
        agents[0].grantors        = new address[](1);
        agents[0].grantors[0]     = makeAddr("agentGrantor");
        agents[0].revokers        = new address[](1);
        agents[0].revokers[0]     = makeAddr("agentRevoker");

        // --- Capture factory nonces to predict deterministic addresses (one CREATE per call).
        //     PAU_FACTORY order: proxy, AC_A, AC_B, RL_A, RL_B, ctrl0, ctrl1.

        uint256 fNonce = vm.getNonce(PAU_FACTORY);
        uint256 aNonce = vm.getNonce(ADMINISTERED_AGENT_FACTORY);

        // --- Deploy.

        (
            address          proxy,
            address[] memory controllers,
            address[] memory accessControls,
            address[] memory rateLimits,
            address[] memory allocatorAgents
        ) = assembler.deploy(ctrls, rls, acs, agents, _proxyConfig());

        // --- Addresses (inlined to keep stack shallow; this contract is built without via-IR).

        assertEq(proxy,              vm.computeCreateAddress(PAU_FACTORY, fNonce));
        assertEq(accessControls[0],  vm.computeCreateAddress(PAU_FACTORY, fNonce + 1));
        assertEq(accessControls[1],  vm.computeCreateAddress(PAU_FACTORY, fNonce + 2));
        assertEq(rateLimits[0],      vm.computeCreateAddress(PAU_FACTORY, fNonce + 3));
        assertEq(rateLimits[1],      vm.computeCreateAddress(PAU_FACTORY, fNonce + 4));
        assertEq(controllers[0],     vm.computeCreateAddress(PAU_FACTORY, fNonce + 5));
        assertEq(controllers[1],     vm.computeCreateAddress(PAU_FACTORY, fNonce + 6));
        assertEq(allocatorAgents[0], vm.computeCreateAddress(ADMINISTERED_AGENT_FACTORY, aNonce));

        // --- Shared ALMProxy: admins set, both controllers granted CONTROLLER, assembler revoked.

        bytes32 proxyController = IALMProxyLike(proxy).CONTROLLER();

        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("proxyAdmin")), true);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE, address(assembler)),     false);
        assertEq(IAccessControlLike(proxy).hasRole(proxyController,    controllers[0]),         true);
        assertEq(IAccessControlLike(proxy).hasRole(proxyController,    controllers[1]),         true);

        // Assembler holds no CONTROLLER on the shared proxy either (proxy/rateLimits are not
        // AccessControlEnumerable, so member counts are only asserted on AccessControls below).
        assertEq(IAccessControlLike(proxy).hasRole(proxyController, address(assembler)), false);

        // --- AccessControls A: admin set, agent has allocator role, assembler revoked.

        assertEq(IAccessControlLike(accessControls[0]).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("acAdminA")), true);
        assertEq(IAccessControlLike(accessControls[0]).hasRole(DEFAULT_ADMIN_ROLE, address(assembler)),   false);
        assertEq(IAccessControlLike(accessControls[0]).hasRole(ALLOCATOR_ROLE,     allocatorAgents[0]),    true);
        assertEq(IAccessControlLike(accessControls[0]).getRoleMemberCount(ALLOCATOR_ROLE),                1);

        // AccessControls B has no allocator (agent referenced AC_A only).
        assertEq(IAccessControlLike(accessControls[1]).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("acAdminB")), true);
        assertEq(IAccessControlLike(accessControls[1]).hasRole(DEFAULT_ADMIN_ROLE, address(assembler)),   false);
        assertEq(IAccessControlLike(accessControls[1]).getRoleMemberCount(ALLOCATOR_ROLE),                0);

        // --- RateLimits: admin set, matching controller granted CONTROLLER, assembler revoked.

        assertEq(IAccessControlLike(rateLimits[0]).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("rlAdminA")), true);
        assertEq(IAccessControlLike(rateLimits[0]).hasRole(DEFAULT_ADMIN_ROLE, address(assembler)),   false);
        assertEq(IAccessControlLike(accessControls[0]).getRoleMemberCount(DEFAULT_ADMIN_ROLE),        1);
        assertEq(IAccessControlLike(rateLimits[0]).hasRole(IRateLimitsLike(rateLimits[0]).CONTROLLER(), controllers[0]), true);
        assertEq(IAccessControlLike(rateLimits[1]).hasRole(IRateLimitsLike(rateLimits[1]).CONTROLLER(), controllers[1]), true);
        // RateLimits A is not wired to controller 1, and vice versa.
        assertEq(IAccessControlLike(rateLimits[0]).hasRole(IRateLimitsLike(rateLimits[0]).CONTROLLER(), controllers[1]), false);

        // --- Controllers: wiring and integrations.

        assertEq(IControllerLike(controllers[0]).proxy(),          proxy);
        assertEq(IControllerLike(controllers[0]).accessControls(), accessControls[0]);
        assertEq(IControllerLike(controllers[0]).rateLimits(),     rateLimits[0]);

        assertEq(IControllerLike(controllers[1]).proxy(),          proxy);
        assertEq(IControllerLike(controllers[1]).accessControls(), accessControls[1]);
        assertEq(IControllerLike(controllers[1]).rateLimits(),     rateLimits[1]);

        assertEq(IControllerLike(controllers[0]).integrations().length,         1);
        assertEq(IControllerLike(controllers[0]).integrations()[0].id,          AAVE_INTEGRATION_ID);
        assertEq(IControllerLike(controllers[0]).integrations()[0].config.facet, AAVE_FACET);

        assertEq(IControllerLike(controllers[1]).integrations().length,         1);
        assertEq(IControllerLike(controllers[1]).integrations()[0].id,          TRANSFER_ASSET_INTEGRATION_ID);
        assertEq(IControllerLike(controllers[1]).integrations()[0].config.facet, TRANSFER_ASSET_FACET);

        // --- Agent configured and self-admin removed.

        IAdministeredAgentLike agent = IAdministeredAgentLike(allocatorAgents[0]);

        assertEq(agent.adminCount(),   1);
        assertEq(agent.actorCount(),   1);
        assertEq(agent.grantorCount(), 1);
        assertEq(agent.revokerCount(), 1);

        assertEq(agent.getIsAdmin(makeAddr("agentAdmin")),     true);
        assertEq(agent.getIsAdmin(address(assembler)),         false);
        assertEq(agent.getIsActor(makeAddr("agentActor")),     true);
        assertEq(agent.getIsGrantor(makeAddr("agentGrantor")), true);
        assertEq(agent.getIsRevoker(makeAddr("agentRevoker")), true);
    }

    function test_deploy_emptyIntegrationIds_skipsUpdate() external {
        // A controller with no integrations must still deploy and wire cleanly.

        IPAUAssembler.AccessControlConfig[] memory acs = new IPAUAssembler.AccessControlConfig[](1);
        acs[0] = _oneAdmin(AC_A, "acAdminA");

        IPAUAssembler.RateLimitConfig[] memory rls = new IPAUAssembler.RateLimitConfig[](1);
        rls[0] = _oneAdminRL(RL_A, "rlAdminA");

        IPAUAssembler.ControllerConfig[] memory ctrls = new IPAUAssembler.ControllerConfig[](1);
        ctrls[0].rateLimitId     = RL_A;
        ctrls[0].accessControlId = AC_A;
        // integrationIds empty

        ( , address[] memory controllers, , , ) =
            assembler.deploy(ctrls, rls, acs, new IPAUAssembler.AdministeredAgentConfig[](0), _proxyConfig());

        assertEq(IControllerLike(controllers[0]).integrations().length, 0);
    }

    function test_deploy_twiceInSameTest_transientCleared() external {
        // Two sequential deploys reuse the same ids; transient cleanup must let the second succeed.

        IPAUAssembler.AccessControlConfig[] memory acs = new IPAUAssembler.AccessControlConfig[](1);
        acs[0] = _oneAdmin(AC_A, "acAdminA");

        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitConfig[](0),
            acs,
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );

        // Same id again — must not revert with a duplicate id from stale transient state.
        acs[0] = _oneAdmin(AC_A, "acAdminA2");

        ( , , address[] memory accessControls, , ) = assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitConfig[](0),
            acs,
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );

        assertEq(IAccessControlLike(accessControls[0]).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("acAdminA2")), true);
    }

}
