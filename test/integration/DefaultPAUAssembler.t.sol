// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IDefaultPAUAssembler } from "../../src/interfaces/IDefaultPAUAssembler.sol";

import { DefaultPAUAssembler } from "../../src/DefaultPAUAssembler.sol";

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
contract DefaultPAUAssembler_Integration_Tests is Test {

    address internal constant PAU_FACTORY                = 0x69A5d548830AC2A4Ba90A44a2C75BDA71f97fc66;
    address internal constant ADMINISTERED_AGENT_FACTORY = 0x2968c3b5478cF93B70aB1e24255d4EDBBd27a089;
    address internal constant AAVE_FACET                 = 0x8CE890A96a193ff2DD4B2eA3C682326F655f6b62;
    address internal constant TRANSFER_ASSET_FACET       = 0x4DA7608C331b8f135df5b985018933780eCd089D;

    bytes32 internal constant DEFAULT_ADMIN_ROLE            = 0x00;
    bytes32 internal constant ALLOCATOR_ROLE                = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant AAVE_INTEGRATION_ID           = "AAVE_FACET";
    bytes32 internal constant TRANSFER_ASSET_INTEGRATION_ID = "TRANSFER_ASSET_FACET";

    DefaultPAUAssembler internal assembler;

    function setUp() external {
        vm.createSelectFork("mainnet", 25270600);

        assembler = new DefaultPAUAssembler(PAU_FACTORY, ADMINISTERED_AGENT_FACTORY);
    }

    function test_deploy() external {
        address admin = makeAddr("admin");

        bytes32[] memory integrationIds = new bytes32[](2);
        integrationIds[0] = AAVE_INTEGRATION_ID;
        integrationIds[1] = TRANSFER_ASSET_INTEGRATION_ID;

        IDefaultPAUAssembler.AdminConfig memory adminConfig = IDefaultPAUAssembler.AdminConfig({
            accessControlAdmins: new address[](2),
            proxyAdmins:         new address[](2),
            rateLimitsAdmins:    new address[](2)
        });

        adminConfig.accessControlAdmins[0] = admin;
        adminConfig.accessControlAdmins[1] = makeAddr("accessControlAdmin");
        adminConfig.proxyAdmins[0]         = admin;
        adminConfig.proxyAdmins[1]         = makeAddr("proxyAdmin");
        adminConfig.rateLimitsAdmins[0]    = admin;
        adminConfig.rateLimitsAdmins[1]    = makeAddr("rateLimitsAdmin");

        IDefaultPAUAssembler.AdministeredAgentConfig[] memory administeredAgentConfigs = new IDefaultPAUAssembler.AdministeredAgentConfig[](2);

        administeredAgentConfigs[0] = IDefaultPAUAssembler.AdministeredAgentConfig({
            admins:   new address[](2),
            actors:   new address[](3),
            grantors: new address[](2),
            revokers: new address[](2)
        });

        administeredAgentConfigs[0].admins[0] = admin;
        administeredAgentConfigs[0].admins[1] = makeAddr("firstAdministeredAgentAdmin");

        administeredAgentConfigs[0].actors[0] = makeAddr("allocator1");
        administeredAgentConfigs[0].actors[1] = makeAddr("allocator2");
        administeredAgentConfigs[0].actors[2] = makeAddr("allocator3");

        administeredAgentConfigs[0].grantors[0] = makeAddr("granter1");
        administeredAgentConfigs[0].grantors[1] = makeAddr("granter2");

        administeredAgentConfigs[0].revokers[0] = makeAddr("revoker1");
        administeredAgentConfigs[0].revokers[1] = makeAddr("revoker2");

        administeredAgentConfigs[1] = IDefaultPAUAssembler.AdministeredAgentConfig({
            admins:   new address[](1),
            actors:   new address[](1),
            grantors: new address[](1),
            revokers: new address[](1)
        });

        administeredAgentConfigs[1].admins[0] = admin;

        administeredAgentConfigs[1].actors[0] = makeAddr("allocator4");

        administeredAgentConfigs[1].grantors[0] = makeAddr("granter3");

        administeredAgentConfigs[1].revokers[0] = makeAddr("revoker3");

        (
            address          proxy,
            address          controller,
            address          accessControls,
            address          rateLimits,
            address[] memory allocatorAgents
        ) = assembler.deploy(integrationIds, adminConfig, administeredAgentConfigs);

        // Assert allocatorAgents state.
        assertEq(allocatorAgents.length, 2);

        assertEq(IAdministeredAgentLike(allocatorAgents[0]).actorCount(),   3);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).adminCount(),   2);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).grantorCount(), 2);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).revokerCount(), 2);

        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsActor(administeredAgentConfigs[0].actors[0]),     true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsActor(administeredAgentConfigs[0].actors[1]),     true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsActor(administeredAgentConfigs[0].actors[2]),     true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsAdmin(administeredAgentConfigs[0].admins[0]),     true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsAdmin(administeredAgentConfigs[0].admins[1]),     true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsGrantor(administeredAgentConfigs[0].grantors[0]), true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsGrantor(administeredAgentConfigs[0].grantors[1]), true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsRevoker(administeredAgentConfigs[0].revokers[0]), true);
        assertEq(IAdministeredAgentLike(allocatorAgents[0]).getIsRevoker(administeredAgentConfigs[0].revokers[1]), true);

        assertEq(IAdministeredAgentLike(allocatorAgents[1]).actorCount(),   1);
        assertEq(IAdministeredAgentLike(allocatorAgents[1]).adminCount(),   1);
        assertEq(IAdministeredAgentLike(allocatorAgents[1]).grantorCount(), 1);
        assertEq(IAdministeredAgentLike(allocatorAgents[1]).revokerCount(), 1);

        assertEq(IAdministeredAgentLike(allocatorAgents[1]).getIsActor(administeredAgentConfigs[1].actors[0]),     true);
        assertEq(IAdministeredAgentLike(allocatorAgents[1]).getIsAdmin(administeredAgentConfigs[1].admins[0]),     true);
        assertEq(IAdministeredAgentLike(allocatorAgents[1]).getIsGrantor(administeredAgentConfigs[1].grantors[0]), true);
        assertEq(IAdministeredAgentLike(allocatorAgents[1]).getIsRevoker(administeredAgentConfigs[1].revokers[0]), true);

        // Assert AccessControls state.
        assertEq(IAccessControlLike(accessControls).getRoleMemberCount(DEFAULT_ADMIN_ROLE), 2);
        assertEq(IAccessControlLike(accessControls).getRoleMemberCount(ALLOCATOR_ROLE),     2);

        assertEq(IAccessControlLike(accessControls).hasRole(DEFAULT_ADMIN_ROLE, adminConfig.accessControlAdmins[0]), true);
        assertEq(IAccessControlLike(accessControls).hasRole(DEFAULT_ADMIN_ROLE, adminConfig.accessControlAdmins[1]), true);
        assertEq(IAccessControlLike(accessControls).hasRole(DEFAULT_ADMIN_ROLE, address(assembler)),                 false);
        assertEq(IAccessControlLike(accessControls).hasRole(ALLOCATOR_ROLE,     allocatorAgents[0]),                 true);
        assertEq(IAccessControlLike(accessControls).hasRole(ALLOCATOR_ROLE,     allocatorAgents[1]),                 true);

        assertEq(IAccessControlLike(accessControls).getRoleAdmin(ALLOCATOR_ROLE), DEFAULT_ADMIN_ROLE);

        // Assert ALMProxy state.
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,                adminConfig.proxyAdmins[0]), true);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,                adminConfig.proxyAdmins[1]), true);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,                address(assembler)),         false);
        assertEq(IAccessControlLike(proxy).hasRole(IALMProxyLike(proxy).CONTROLLER(), controller),                 true);

        // Assert Controller state.
        assertEq(IControllerLike(controller).accessControls(), accessControls);
        assertEq(IControllerLike(controller).beacon(),         IPAUFactoryLike(PAU_FACTORY).beacon());
        assertEq(IControllerLike(controller).proxy(),          proxy);
        assertEq(IControllerLike(controller).rateLimits(),     rateLimits);

        assertEq(IControllerLike(controller).integrations().length, 2);

        assertEq(IControllerLike(controller).integrations()[0].id, AAVE_INTEGRATION_ID);
        assertEq(IControllerLike(controller).integrations()[1].id, TRANSFER_ASSET_INTEGRATION_ID);

        assertEq(IControllerLike(controller).integrations()[0].config.facet, AAVE_FACET);
        assertEq(IControllerLike(controller).integrations()[1].config.facet, TRANSFER_ASSET_FACET);

        assertEq(IControllerLike(controller).integrations()[0].config.wires.length, 7);
        assertEq(IControllerLike(controller).integrations()[1].config.wires.length, 3);

        // Assert RateLimits state.
        assertEq(IAccessControlLike(rateLimits).hasRole(DEFAULT_ADMIN_ROLE,                       adminConfig.rateLimitsAdmins[0]), true);
        assertEq(IAccessControlLike(rateLimits).hasRole(DEFAULT_ADMIN_ROLE,                       adminConfig.rateLimitsAdmins[1]), true);
        assertEq(IAccessControlLike(rateLimits).hasRole(DEFAULT_ADMIN_ROLE,                       address(assembler)),                false);
        assertEq(IAccessControlLike(rateLimits).hasRole(IRateLimitsLike(rateLimits).CONTROLLER(), controller),                      true);
    }

}
