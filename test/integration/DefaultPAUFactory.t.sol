// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { Beacon }     from "../../lib/diamond-pau/src/Beacon.sol";
import { PAUFactory } from "../../lib/diamond-pau/src/PAUFactory.sol";

import { AdministeredAgentFactory } from "../../lib/pau-administered-agent/src/AdministeredAgentFactory.sol";

import { IDefaultPAUFactory } from "../../src/interfaces/IDefaultPAUFactory.sol";

import { DefaultPAUFactory } from "../../src/DefaultPAUFactory.sol";

interface IAdministeredAgentLike {

    function getIsAdmin(address account) external view returns (bool);

}

interface IAccessControlLike {

    function hasRole(bytes32 role, address account) external view returns (bool);

}

interface IALMProxyLike {

    function CONTROLLER() external view returns (bytes32);

}

/**
 * @notice Integration coverage against the *canonical* diamond-pau PAUFactory and the real
 *         AdministeredAgentFactory (no mocks). Exercises the adapter against the real bytecode.
 */
contract DefaultPAUFactory_Integration_Tests is Test {

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");

    address internal beaconAdmin = makeAddr("beaconAdmin");

    address internal beacon;
    address internal pauFactory;
    address internal administeredAgentFactory;

    DefaultPAUFactory internal factory;

    function setUp() external {
        beacon                   = address(new Beacon(beaconAdmin));
        pauFactory               = address(new PAUFactory(beacon));
        administeredAgentFactory = address(new AdministeredAgentFactory());

        factory = new DefaultPAUFactory(pauFactory, administeredAgentFactory);
    }

    function test_deploy_standard() external {
        address[] memory admins = new address[](1);
        admins[0] = makeAddr("admin");

        IDefaultPAUFactory.AdminConfig memory adminConfig = IDefaultPAUFactory.AdminConfig({
            accessControlAdmins:     admins,
            proxyAdmins:             admins,
            rateLimitsAdmins:        admins,
            administeredAgentAdmins: admins
        });

        address[] memory allocators = new address[](2);
        allocators[0] = makeAddr("allocator1");
        allocators[1] = makeAddr("allocator2");

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

        // Assert ALMProxy roles.
        assertEq(IAccessControlLike(proxy).hasRole(IALMProxyLike(proxy).CONTROLLER(), controller),       true);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,                admins[0]),        true);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE,                address(factory)), false);
    }

}
