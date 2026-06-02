// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { PAUAdministeredAgentFactory } from "../../src/PAUAdministeredAgentFactory.sol";

import {
    IPAUFactoryLike,
    IAdministeredAgentFactoryLike
} from "../../src/PAUAdministeredAgentFactory.sol";

import { IPAUAdministeredAgentFactory } from "../../src/interfaces/IPAUAdministeredAgentFactory.sol";

import { Beacon }     from "../../lib/diamond-pau/src/Beacon.sol";
import { PAUFactory } from "../../lib/diamond-pau/src/PAUFactory.sol";

import { IEnumerableIntegrations } from "../../lib/diamond-pau/src/interfaces/IEnumerableIntegrations.sol";

import { TransferAssetFacet }  from "../../lib/diamond-pau/src/facets/transfer-asset/TransferAssetFacet.sol";
import { ITransferAssetFacet } from "../../lib/diamond-pau/src/facets/transfer-asset/ITransferAssetFacet.sol";

import { AdministeredAgentFactory } from "../../lib/pau-administered-agent/src/AdministeredAgentFactory.sol";
import { IAdministeredAgent }        from "../../lib/pau-administered-agent/src/interfaces/IAdministeredAgent.sol";

import { MockERC20 } from "../mocks/Mocks.sol";

interface IRateLimitSetter {
    function setUnlimitedRateLimitData(bytes32 key) external;
}

interface IFreezableProxy {
    function removeAllocator(address allocator) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function ALLOCATOR_ROLE() external view returns (bytes32);
}

/**
 * @notice Full end-to-end integration: the factory deploys a real PAU stack (real Beacon,
 *         PAUFactory, Controller, ALMProxy, RateLimits) with a real TransferAssetFacet integration
 *         registered, then an actor routes a real ERC20 transfer through
 *         AdministeredAgent -> Controller -> facet -> ALMProxy -> token.
 */
contract PAUAdministeredAgentFactory_TransferAsset_Integration_Tests is Test {

    bytes32 internal constant INTEGRATION_ID = "TRANSFER_ASSET_FACET";

    address internal admin       = makeAddr("admin");
    address internal beaconAdmin = makeAddr("beaconAdmin");
    address internal actor       = makeAddr("actor");
    address internal recipient   = makeAddr("recipient");

    Beacon                      internal beacon;
    PAUFactory                  internal pauFactory;
    AdministeredAgentFactory    internal agentFactory;
    PAUAdministeredAgentFactory internal factory;
    TransferAssetFacet          internal facet;
    MockERC20                   internal token;

    function setUp() external {
        beacon       = new Beacon(beaconAdmin);
        pauFactory   = new PAUFactory(address(beacon));
        agentFactory = new AdministeredAgentFactory();
        factory      = new PAUAdministeredAgentFactory(
            IPAUFactoryLike(address(pauFactory)),
            IAdministeredAgentFactoryLike(address(agentFactory))
        );

        facet = new TransferAssetFacet();
        token = new MockERC20();

        // Register the facet on the Beacon so the factory's updateIntegrations can sync it.
        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](1);
        wires[0] = IEnumerableIntegrations.Wire(
            ITransferAssetFacet.transfer.selector,
            ITransferAssetFacet.transfer.selector
        );

        vm.prank(beaconAdmin);
        beacon.setIntegration(INTEGRATION_ID, IEnumerableIntegrations.Config(address(facet), wires));
    }

    function test_endToEnd_transferAssetThroughDeployedStack() external {
        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = INTEGRATION_ID;

        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig =
            IPAUAdministeredAgentFactory.AdminConfig({
                accessControlAdmins:     new address[](0),
                proxyAdmins:             new address[](0),
                rateLimitsAdmins:        new address[](0),
                administeredAgentAdmins: new address[](0)
            });

        address[] memory actors = new address[](1);
        actors[0] = actor;

        IPAUAdministeredAgentFactory.AdministeredAgentConfig memory agentConfig =
            IPAUAdministeredAgentFactory.AdministeredAgentConfig({
                actors:   actors,
                grantors: new address[](0),
                revokers: new address[](0)
            });

        (
            ,
            address controller,
            address proxy,
            address rateLimits,
            address agent
        ) = factory.deploy(
            admin,
            integrationIds,
            adminConfig,
            agentConfig,
            new IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig[](0)
        );

        // Fund the proxy and open the rate limit for this asset/destination pair.
        token.mint(address(proxy), 1_000e18);

        bytes32 key = facet.getTransferRateLimitKey(address(token), recipient);
        vm.prank(admin);
        IRateLimitSetter(address(rateLimits)).setUnlimitedRateLimitData(key);

        // The actor routes a transfer through the agent (allocator) -> controller -> facet -> proxy.
        bytes memory transferCall =
            abi.encodeWithSelector(ITransferAssetFacet.transfer.selector, address(token), recipient, 100e18);

        vm.prank(actor);
        IAdministeredAgent(address(agent)).call(address(controller), transferCall);

        assertEq(token.balanceOf(recipient),      100e18);
        assertEq(token.balanceOf(address(proxy)), 900e18);
    }

    // Sanity: only an actor on the agent can drive the transfer.
    function test_endToEnd_revertsForNonActor() external {
        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = INTEGRATION_ID;

        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig =
            IPAUAdministeredAgentFactory.AdminConfig({
                accessControlAdmins:     new address[](0),
                proxyAdmins:             new address[](0),
                rateLimitsAdmins:        new address[](0),
                administeredAgentAdmins: new address[](0)
            });

        ( , address controller, , , address agent) = factory.deploy(
            admin,
            integrationIds,
            adminConfig,
            IPAUAdministeredAgentFactory.AdministeredAgentConfig({
                actors:   new address[](0),
                grantors: new address[](0),
                revokers: new address[](0)
            }),
            new IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig[](0)
        );

        bytes memory transferCall =
            abi.encodeWithSelector(ITransferAssetFacet.transfer.selector, address(token), recipient, 1e18);

        vm.prank(actor);
        vm.expectRevert(IAdministeredAgent.NotActor.selector);
        IAdministeredAgent(address(agent)).call(address(controller), transferCall);
    }

    // Freezable variant: a real transfer works, then a freezer removes the Controller as the proxy's
    // allocator and subsequent transfers revert (the freezable proxy gates `doCall` on ALLOCATOR_ROLE,
    // which the freezer revoked from the Controller).
    function test_endToEnd_freezableProxy_freezeHaltsTransfers() external {
        address freezer = makeAddr("freezer");

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = INTEGRATION_ID;

        address[] memory freezers = new address[](1);
        freezers[0] = freezer;

        address[] memory actors = new address[](1);
        actors[0] = actor;

        IPAUAdministeredAgentFactory.AdminConfig memory adminConfig =
            IPAUAdministeredAgentFactory.AdminConfig({
                accessControlAdmins:     new address[](0),
                proxyAdmins:             new address[](0),
                rateLimitsAdmins:        new address[](0),
                administeredAgentAdmins: new address[](0)
            });

        IPAUAdministeredAgentFactory.AdministeredAgentConfig memory agentConfig =
            IPAUAdministeredAgentFactory.AdministeredAgentConfig({
                actors:   actors,
                grantors: new address[](0),
                revokers: new address[](0)
            });

        // (i) deploy the freezable variant.
        (
            ,
            address controller,
            address proxy,
            address rateLimits,
            address agent
        ) = factory.deployFreezable(
            admin,
            freezers,
            integrationIds,
            adminConfig,
            agentConfig,
            new IPAUAdministeredAgentFactory.AccessControlRoleAdminConfig[](0)
        );

        // Fund the proxy and open the rate limit.
        token.mint(proxy, 1_000e18);

        bytes32 key = facet.getTransferRateLimitKey(address(token), recipient);
        vm.prank(admin);
        IRateLimitSetter(rateLimits).setUnlimitedRateLimitData(key);

        bytes memory transferCall =
            abi.encodeWithSelector(ITransferAssetFacet.transfer.selector, address(token), recipient, 100e18);

        // (ii) a real transfer works through the freezable proxy.
        vm.prank(actor);
        IAdministeredAgent(agent).call(controller, transferCall);
        assertEq(token.balanceOf(recipient), 100e18);
        assertEq(token.balanceOf(proxy),     900e18);

        // The Controller is the proxy's allocator until frozen.
        bytes32 allocatorRole = IFreezableProxy(proxy).ALLOCATOR_ROLE();
        assertTrue(IFreezableProxy(proxy).hasRole(allocatorRole, controller));

        // (iii) a freezer removes the Controller as allocator.
        vm.prank(freezer);
        IFreezableProxy(proxy).removeAllocator(controller);
        assertFalse(IFreezableProxy(proxy).hasRole(allocatorRole, controller));

        // (iv) subsequent transfers revert — the proxy's `doCall` is no longer authorized for the Controller.
        vm.prank(actor);
        vm.expectRevert();
        IAdministeredAgent(agent).call(controller, transferCall);

        // Balances unchanged after the failed transfer.
        assertEq(token.balanceOf(recipient), 100e18);
        assertEq(token.balanceOf(proxy),     900e18);
    }

}
