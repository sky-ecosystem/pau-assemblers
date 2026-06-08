// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IDefaultPAUFactory } from "../../src/interfaces/IDefaultPAUFactory.sol";

import { DefaultPAUFactory } from "../../src/DefaultPAUFactory.sol";

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

    function beacon() external view returns (address);

    function integrations() external view returns (Integration[] memory);

    function proxy() external view returns (address);

    function rateLimits() external view returns (address);

}

interface IRateLimitsLike {

    function CONTROLLER() external view returns (bytes32);

}

interface IPAUFactoryLike {

    function beacon() external view returns (address);

}

/**
 * @notice Integration coverage against the *canonical* diamond-pau PAUFactory and the real
 *         AdministeredAgentFactory (no mocks). Exercises the adapter against the real bytecode.
 */
contract DefaultPAUFactory_Integration_Tests is Test {

    address internal constant PAU_FACTORY                = 0x69A5d548830AC2A4Ba90A44a2C75BDA71f97fc66;
    address internal constant ADMINISTERED_AGENT_FACTORY = 0x2968c3b5478cF93B70aB1e24255d4EDBBd27a089;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");

    DefaultPAUFactory internal factory;

    function setUp() external {
        vm.createSelectFork("mainnet", 25270600);

        factory = new DefaultPAUFactory(PAU_FACTORY, ADMINISTERED_AGENT_FACTORY);
    }

    function test_deploy_standard() external {
        address[] memory admins = new address[](1);
        admins[0] = makeAddr("admin");

        IDefaultPAUFactory.AdminConfig memory adminConfig = IDefaultPAUFactory.AdminConfig({
            accessControlAdmins: admins,
            proxyAdmins:         admins,
            rateLimitsAdmins:    admins
        });

        address[] memory allocators = new address[](3);
        allocators[0] = makeAddr("allocator1");
        allocators[1] = makeAddr("allocator2");
        allocators[2] = makeAddr("allocator3");

        address[] memory freezers = new address[](2);
        freezers[0] = makeAddr("freezer1");
        freezers[1] = makeAddr("freezer2");

        IDefaultPAUFactory.AdministeredAgentConfig memory administeredAgentConfig = IDefaultPAUFactory.AdministeredAgentConfig({
            admins:   admins,
            actors:   allocators,
            grantors: new address[](0),
            revokers: freezers
        });

        IDefaultPAUFactory.AdministeredAgentConfig[] memory administeredAgentConfigs = new IDefaultPAUFactory.AdministeredAgentConfig[](1);
        administeredAgentConfigs[0] = administeredAgentConfig;

        (
            address          proxy,
            address          controller,
            address          accessControls,
            address          rateLimits,
            address[] memory allocatorAgents
        ) = factory.deploy(new bytes32[](0), adminConfig, administeredAgentConfigs);

        // Assert allocatorAgents state.
        assertEq(allocatorAgents.length, 1);

        assertEq(IAdministeredAgentLike(allocatorAgents[0]).actorCount(), 3);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).adminCount(), 1);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).grantorCount(), 0);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).revokerCount(), 2);

        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsActor(allocators[0]), true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsActor(allocators[1]), true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsActor(allocators[2]), true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsAdmin(admins[0]),     true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsRevoker(freezers[0]), true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsRevoker(freezers[1]), true);

        // Assert AccessControls state.
        assertEq(IAccessControlLike(accessControls).getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(IAccessControlLike(accessControls).getRoleMemberCount(ALLOCATOR_ROLE),     1);

        assertEq(IAccessControlLike(accessControls).hasRole(DEFAULT_ADMIN_ROLE, admins[0]),          true);
        assertEq(IAccessControlLike(accessControls).hasRole(DEFAULT_ADMIN_ROLE, address(factory)),   false);
        assertEq(IAccessControlLike(accessControls).hasRole(ALLOCATOR_ROLE,     allocatorAgents[0]), true);

        assertEq(IAccessControlLike(accessControls).getRoleAdmin(ALLOCATOR_ROLE), DEFAULT_ADMIN_ROLE);

        // Assert ALMProxy state.
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,                admins[0]),        true);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,                address(factory)), false);
        assertEq(IAccessControlLike(proxy).hasRole(IALMProxyLike(proxy).CONTROLLER(), controller),       true);

        // Assert Controller state.
        assertEq(IControllerLike(controller).accessControls(), accessControls);
        assertEq(IControllerLike(controller).beacon(),         IPAUFactoryLike(PAU_FACTORY).beacon());
        assertEq(IControllerLike(controller).proxy(),          proxy);
        assertEq(IControllerLike(controller).rateLimits(),     rateLimits);

        assertEq(IControllerLike(controller).integrations().length, 0);

        // Assert RateLimits state.
        assertEq(IAccessControlLike(rateLimits).hasRole(DEFAULT_ADMIN_ROLE,                       admins[0]),        true);
        assertEq(IAccessControlLike(rateLimits).hasRole(DEFAULT_ADMIN_ROLE,                       address(factory)), false);
        assertEq(IAccessControlLike(rateLimits).hasRole(IRateLimitsLike(rateLimits).CONTROLLER(), controller),       true);
    }

}
