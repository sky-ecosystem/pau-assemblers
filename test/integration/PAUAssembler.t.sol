// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IPAUAssembler } from "../../src/interfaces/IPAUAssembler.sol";

import { PAUAssembler } from "../../src/PAUAssembler.sol";

interface IALMProxyLike {

    function CONTROLLER() external view returns (bytes32);

}

interface IAccessControlEnumerableLike {

    function getRoleMemberCount(bytes32 role) external view returns (uint256);

}

interface IAccessControlLike {

    function hasRole(bytes32 role, address account) external view returns (bool);

}

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

    bytes32 internal constant ACCESS_CONTROLS_ID_A = "ACCESS_CONTROLS_A";
    bytes32 internal constant ACCESS_CONTROLS_ID_B = "ACCESS_CONTROLS_B";
    bytes32 internal constant RATE_LIMITS_ID_A     = "RATE_LIMITS_A";
    bytes32 internal constant RATE_LIMITS_ID_B     = "RATE_LIMITS_B";

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

    function _getOneAdminAccessControlsConfig(bytes32 id, string memory adminLabel)
        internal
        returns (IPAUAssembler.AccessControlsConfig memory config)
    {
        config.id        = id;
        config.admins    = new address[](1);
        config.admins[0] = makeAddr(adminLabel);
    }

    function _getOneAdminRateLimitsConfig(bytes32 id, string memory adminLabel)
        internal
        returns (IPAUAssembler.RateLimitsConfig memory config)
    {
        config.id        = id;
        config.admins    = new address[](1);
        config.admins[0] = makeAddr(adminLabel);
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
            new IPAUAssembler.RateLimitsConfig[](0),
            new IPAUAssembler.AccessControlsConfig[](0),
            new IPAUAssembler.AdministeredAgentConfig[](0),
            proxyConfig
        );
    }

    function test_deploy_noProxyAdmins() external {
        IPAUAssembler.ALMProxyConfig memory proxyConfig; // empty admins

        vm.expectRevert(IPAUAssembler.NoDefaultAdmins.selector);
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitsConfig[](0),
            new IPAUAssembler.AccessControlsConfig[](0),
            new IPAUAssembler.AdministeredAgentConfig[](0),
            proxyConfig
        );
    }

    function test_deploy_duplicateAccessControlsId() external {
        IPAUAssembler.AccessControlsConfig[] memory accessControlsConfigs = new IPAUAssembler.AccessControlsConfig[](2);
        accessControlsConfigs[0] = _getOneAdminAccessControlsConfig(ACCESS_CONTROLS_ID_A, "acAdmin0");
        accessControlsConfigs[1] = _getOneAdminAccessControlsConfig(ACCESS_CONTROLS_ID_A, "acAdmin1");

        vm.expectRevert(abi.encodeWithSelector(IPAUAssembler.DuplicateAccessControlsId.selector, ACCESS_CONTROLS_ID_A));
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitsConfig[](0),
            accessControlsConfigs,
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );
    }

    function test_deploy_duplicateRateLimitsId() external {
        IPAUAssembler.RateLimitsConfig[] memory rateLimitsConfigs = new IPAUAssembler.RateLimitsConfig[](2);
        rateLimitsConfigs[0] = _getOneAdminRateLimitsConfig(RATE_LIMITS_ID_A, "rlAdmin0");
        rateLimitsConfigs[1] = _getOneAdminRateLimitsConfig(RATE_LIMITS_ID_A, "rlAdmin1");

        vm.expectRevert(abi.encodeWithSelector(IPAUAssembler.DuplicateRateLimitsId.selector, RATE_LIMITS_ID_A));
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            rateLimitsConfigs,
            new IPAUAssembler.AccessControlsConfig[](0),
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );
    }

    function test_deploy_invalidRateLimitsId() external {
        IPAUAssembler.AccessControlsConfig[] memory accessControlsConfigs = new IPAUAssembler.AccessControlsConfig[](1);
        accessControlsConfigs[0] = _getOneAdminAccessControlsConfig(ACCESS_CONTROLS_ID_A, "acAdmin0");

        IPAUAssembler.ControllerConfig[] memory controllerConfigs = new IPAUAssembler.ControllerConfig[](1);
        controllerConfigs[0] = IPAUAssembler.ControllerConfig({
            integrationIds   : new bytes32[](0),
            rateLimitsId     : RATE_LIMITS_ID_A, // never deployed
            accessControlsId : ACCESS_CONTROLS_ID_A
        });

        vm.expectRevert(abi.encodeWithSelector(IPAUAssembler.InvalidRateLimitsId.selector, RATE_LIMITS_ID_A));
        assembler.deploy(
            controllerConfigs,
            new IPAUAssembler.RateLimitsConfig[](0),
            accessControlsConfigs,
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );
    }

    function test_deploy_invalidAccessControlsId_controller() external {
        IPAUAssembler.RateLimitsConfig[] memory rateLimitsConfigs = new IPAUAssembler.RateLimitsConfig[](1);
        rateLimitsConfigs[0] = _getOneAdminRateLimitsConfig(RATE_LIMITS_ID_A, "rlAdmin0");

        IPAUAssembler.ControllerConfig[] memory controllerConfigs = new IPAUAssembler.ControllerConfig[](1);
        controllerConfigs[0] = IPAUAssembler.ControllerConfig({
            integrationIds   : new bytes32[](0),
            rateLimitsId     : RATE_LIMITS_ID_A,
            accessControlsId : ACCESS_CONTROLS_ID_A // never deployed
        });

        vm.expectRevert(abi.encodeWithSelector(IPAUAssembler.InvalidAccessControlsId.selector, ACCESS_CONTROLS_ID_A));
        assembler.deploy(
            controllerConfigs,
            rateLimitsConfigs,
            new IPAUAssembler.AccessControlsConfig[](0),
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );
    }

    function test_deploy_invalidAccessControlsId_agent() external {
        IPAUAssembler.AdministeredAgentConfig[] memory agentConfigs = new IPAUAssembler.AdministeredAgentConfig[](1);
        agentConfigs[0].accessControlsId = ACCESS_CONTROLS_ID_A; // never deployed
        agentConfigs[0].admins           = new address[](1);
        agentConfigs[0].admins[0]        = makeAddr("agentAdmin");

        vm.expectRevert(abi.encodeWithSelector(IPAUAssembler.InvalidAccessControlsId.selector, ACCESS_CONTROLS_ID_A));
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitsConfig[](0),
            new IPAUAssembler.AccessControlsConfig[](0),
            agentConfigs,
            _proxyConfig()
        );
    }

    function test_deploy_noAgentAdmins() external {
        IPAUAssembler.AccessControlsConfig[] memory accessControlsConfigs = new IPAUAssembler.AccessControlsConfig[](1);
        accessControlsConfigs[0] = _getOneAdminAccessControlsConfig(ACCESS_CONTROLS_ID_A, "acAdmin0");

        IPAUAssembler.AdministeredAgentConfig[] memory agentConfigs = new IPAUAssembler.AdministeredAgentConfig[](1);
        agentConfigs[0].accessControlsId = ACCESS_CONTROLS_ID_A;
        // admins empty

        vm.expectRevert(IPAUAssembler.NoAgentAdmins.selector);
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitsConfig[](0),
            accessControlsConfigs,
            agentConfigs,
            _proxyConfig()
        );
    }

    function test_deploy_noAccessControlAdmins() external {
        IPAUAssembler.AccessControlsConfig[] memory accessControlsConfigs = new IPAUAssembler.AccessControlsConfig[](1);
        accessControlsConfigs[0].id = ACCESS_CONTROLS_ID_A; // admins empty

        vm.expectRevert(IPAUAssembler.NoDefaultAdmins.selector);
        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitsConfig[](0),
            accessControlsConfigs,
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );
    }

    /**********************************************************************************************/
    /*** deploy Happy Path                                                                       ***/
    /**********************************************************************************************/

    function test_deploy() external {
        // --- Build configs: 2 AccessControls, 2 RateLimits, 2 Controllers (one per pair), 1 agent.

        IPAUAssembler.AccessControlsConfig[] memory accessControlsConfigs = new IPAUAssembler.AccessControlsConfig[](2);
        accessControlsConfigs[0] = _getOneAdminAccessControlsConfig(ACCESS_CONTROLS_ID_A, "acAdminA");
        accessControlsConfigs[1] = _getOneAdminAccessControlsConfig(ACCESS_CONTROLS_ID_B, "acAdminB");

        IPAUAssembler.RateLimitsConfig[] memory rateLimitsConfigs = new IPAUAssembler.RateLimitsConfig[](2);
        rateLimitsConfigs[0] = _getOneAdminRateLimitsConfig(RATE_LIMITS_ID_A, "rlAdminA");
        rateLimitsConfigs[1] = _getOneAdminRateLimitsConfig(RATE_LIMITS_ID_B, "rlAdminB");

        IPAUAssembler.ControllerConfig[] memory controllerConfigs = new IPAUAssembler.ControllerConfig[](2);

        controllerConfigs[0].integrationIds    = new bytes32[](1);
        controllerConfigs[0].integrationIds[0] = AAVE_INTEGRATION_ID;
        controllerConfigs[0].rateLimitsId      = RATE_LIMITS_ID_A;
        controllerConfigs[0].accessControlsId  = ACCESS_CONTROLS_ID_A;

        controllerConfigs[1].integrationIds    = new bytes32[](1);
        controllerConfigs[1].integrationIds[0] = TRANSFER_ASSET_INTEGRATION_ID;
        controllerConfigs[1].rateLimitsId      = RATE_LIMITS_ID_B;
        controllerConfigs[1].accessControlsId  = ACCESS_CONTROLS_ID_B;

        IPAUAssembler.AdministeredAgentConfig[] memory agentConfigs = new IPAUAssembler.AdministeredAgentConfig[](1);
        agentConfigs[0].accessControlsId = ACCESS_CONTROLS_ID_A;
        agentConfigs[0].admins           = new address[](1);
        agentConfigs[0].admins[0]        = makeAddr("agentAdmin");
        agentConfigs[0].actors           = new address[](1);
        agentConfigs[0].actors[0]        = makeAddr("agentActor");
        agentConfigs[0].grantors         = new address[](1);
        agentConfigs[0].grantors[0]      = makeAddr("agentGrantor");
        agentConfigs[0].revokers         = new address[](1);
        agentConfigs[0].revokers[0]      = makeAddr("agentRevoker");

        // --- Capture factory nonces to predict deterministic addresses (one CREATE per call).
        //     PAU_FACTORY order: proxy, AccessControls A/B, RateLimits A/B, controllers 0/1.

        uint256 pauFactoryNonce = vm.getNonce(PAU_FACTORY);
        uint256 agentFactoryNonce = vm.getNonce(ADMINISTERED_AGENT_FACTORY);

        // --- Deploy.

        (
            address          proxy,
            address[] memory controllers,
            address[] memory accessControls,
            address[] memory rateLimits,
            address[] memory allocatorAgents
        ) = assembler.deploy(controllerConfigs, rateLimitsConfigs, accessControlsConfigs, agentConfigs, _proxyConfig());

        // --- Addresses (inlined to keep stack shallow; this contract is built without via-IR).

        assertEq(proxy,              vm.computeCreateAddress(PAU_FACTORY, pauFactoryNonce));
        assertEq(accessControls[0],  vm.computeCreateAddress(PAU_FACTORY, pauFactoryNonce + 1));
        assertEq(accessControls[1],  vm.computeCreateAddress(PAU_FACTORY, pauFactoryNonce + 2));
        assertEq(rateLimits[0],      vm.computeCreateAddress(PAU_FACTORY, pauFactoryNonce + 3));
        assertEq(rateLimits[1],      vm.computeCreateAddress(PAU_FACTORY, pauFactoryNonce + 4));
        assertEq(controllers[0],     vm.computeCreateAddress(PAU_FACTORY, pauFactoryNonce + 5));
        assertEq(controllers[1],     vm.computeCreateAddress(PAU_FACTORY, pauFactoryNonce + 6));

        assertEq(allocatorAgents[0], vm.computeCreateAddress(ADMINISTERED_AGENT_FACTORY, agentFactoryNonce));

        // --- Shared ALMProxy: admins set, both controllers granted CONTROLLER, assembler revoked.

        bytes32 proxyControllerRole = IALMProxyLike(proxy).CONTROLLER();

        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,     makeAddr("proxyAdmin")), true);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,     address(assembler)),     false);
        assertEq(IAccessControlLike(proxy).hasRole(proxyControllerRole,    controllers[0]),         true);
        assertEq(IAccessControlLike(proxy).hasRole(proxyControllerRole,    controllers[1]),         true);

        // Assembler holds no CONTROLLER on the shared proxy either (proxy/rateLimits are not
        // AccessControlEnumerable, so member counts are only asserted on AccessControls below).
        assertEq(IAccessControlLike(proxy).hasRole(proxyControllerRole, address(assembler)), false);

        // --- AccessControls A: admin set, agent has allocator role, assembler revoked.

        assertEq(IAccessControlLike(accessControls[0]).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("acAdminA")), true);
        assertEq(IAccessControlLike(accessControls[0]).hasRole(DEFAULT_ADMIN_ROLE, address(assembler)),   false);
        assertEq(IAccessControlLike(accessControls[0]).hasRole(ALLOCATOR_ROLE,     allocatorAgents[0]),   true);
        assertEq(IAccessControlEnumerableLike(accessControls[0]).getRoleMemberCount(ALLOCATOR_ROLE),      1);
        assertEq(IAccessControlEnumerableLike(accessControls[0]).getRoleMemberCount(DEFAULT_ADMIN_ROLE),  1);

        // AccessControls B has no allocator (agent referenced ACCESS_CONTROLS_ID_A only).
        assertEq(IAccessControlLike(accessControls[1]).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("acAdminB")), true);
        assertEq(IAccessControlLike(accessControls[1]).hasRole(DEFAULT_ADMIN_ROLE, address(assembler)),   false);
        assertEq(IAccessControlEnumerableLike(accessControls[1]).getRoleMemberCount(ALLOCATOR_ROLE),      0);
        assertEq(IAccessControlEnumerableLike(accessControls[1]).getRoleMemberCount(DEFAULT_ADMIN_ROLE),  1);

        // --- RateLimits: admin set, matching controller granted CONTROLLER, assembler revoked.

        assertEq(IAccessControlLike(rateLimits[0]).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("rlAdminA")), true);
        assertEq(IAccessControlLike(rateLimits[0]).hasRole(DEFAULT_ADMIN_ROLE, address(assembler)),   false);
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

        assertEq(IControllerLike(controllers[0]).integrations().length,          1);
        assertEq(IControllerLike(controllers[0]).integrations()[0].id,           AAVE_INTEGRATION_ID);
        assertEq(IControllerLike(controllers[0]).integrations()[0].config.facet, AAVE_FACET);

        assertEq(IControllerLike(controllers[1]).integrations().length,          1);
        assertEq(IControllerLike(controllers[1]).integrations()[0].id,           TRANSFER_ASSET_INTEGRATION_ID);
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

        IPAUAssembler.AccessControlsConfig[] memory accessControlsConfigs = new IPAUAssembler.AccessControlsConfig[](1);
        accessControlsConfigs[0] = _getOneAdminAccessControlsConfig(ACCESS_CONTROLS_ID_A, "acAdminA");

        IPAUAssembler.RateLimitsConfig[] memory rateLimitsConfigs = new IPAUAssembler.RateLimitsConfig[](1);
        rateLimitsConfigs[0] = _getOneAdminRateLimitsConfig(RATE_LIMITS_ID_A, "rlAdminA");

        IPAUAssembler.ControllerConfig[] memory controllerConfigs = new IPAUAssembler.ControllerConfig[](1);
        controllerConfigs[0].rateLimitsId     = RATE_LIMITS_ID_A;
        controllerConfigs[0].accessControlsId = ACCESS_CONTROLS_ID_A;
        // integrationIds empty

        ( , address[] memory controllers, , , ) =
            assembler.deploy(controllerConfigs, rateLimitsConfigs, accessControlsConfigs, new IPAUAssembler.AdministeredAgentConfig[](0), _proxyConfig());

        assertEq(IControllerLike(controllers[0]).integrations().length, 0);
    }

    function test_deploy_twiceInSameTest_transientCleared() external {
        // Two sequential deploys reuse the same ids; transient cleanup must let the second succeed.

        IPAUAssembler.AccessControlsConfig[] memory accessControlsConfigs = new IPAUAssembler.AccessControlsConfig[](1);
        accessControlsConfigs[0] = _getOneAdminAccessControlsConfig(ACCESS_CONTROLS_ID_A, "acAdminA");

        assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitsConfig[](0),
            accessControlsConfigs,
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );

        // Same id again — must not revert with a duplicate id from stale transient state.
        accessControlsConfigs[0] = _getOneAdminAccessControlsConfig(ACCESS_CONTROLS_ID_A, "acAdminA2");

        ( , , address[] memory accessControls, , ) = assembler.deploy(
            new IPAUAssembler.ControllerConfig[](0),
            new IPAUAssembler.RateLimitsConfig[](0),
            accessControlsConfigs,
            new IPAUAssembler.AdministeredAgentConfig[](0),
            _proxyConfig()
        );

        assertEq(IAccessControlLike(accessControls[0]).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("acAdminA2")), true);
    }

}
