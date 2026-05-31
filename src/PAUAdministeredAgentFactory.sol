// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IPAUAdministeredAgentFactory } from "./interfaces/PAUAdministeredAgentFactory.sol";

interface IPAUFactoryLike {

    function deployAccessControls(address admin) external returns(address accessControls);

    function deployController(address accessControls, address proxy, address rateLimits)
            external
            returns (address controller);

    function deployProxy(address admin) external returns (address proxy);

    function deployProxyFreezable(address admin) external returns (address proxy);

    function deployRateLimits(address admin) external returns (address rateLimits);

}

interface IAdministeredAgentFactoryLike {

    function deploy(address admin) external returns(address);

}

interface IRateLimitsLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function CONTROLLER() external view returns (bytes32);

}

interface IALMProxyLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function CONTROLLER() external view returns (bytes32);

}

interface IAccessControlsLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function setRoleAdmin(bytes32 role, address admin) external;
}

interface IControllerLike {

    function updateIntegrations(bytes32[] calldata ids) external;
}

interface IAdministeredAgentLike {

    function addAdmin(address admin) external;

    function removeAdmin(address admin) external;

    function addGrantor(address grantor) external;

    function addRevoker(address revoker) external;

    function addActor(address actor) external;

}

/**
 * @title  PAUAdministeredAgentFactory
 * @notice One-shot helper that deploys and wires together a full PAU stack
 *         (AccessControls, ALMProxy, RateLimits, Controller) plus an
 *         AdministeredAgent, registers integrations, configures the agent, and
 *         hands all admin rights to the caller-supplied admin while renouncing
 *         its own.
 */
contract PAUAdministeredAgentFactory is IPAUAdministeredAgentFactory {

    /// @inheritdoc IPAUAdministeredAgentFactory
    IPAUFactoryLike public immutable override pauFactory;

    /// @inheritdoc IPAUAdministeredAgentFactory
    IAdministeredAgentFactoryLike public immutable override administeredAgentFactory;

    bytes32 internal constant _DEFAULT_ADMIN_ROLE = 0x00;

    /// @inheritdoc IPAUAdministeredAgentFactory
    bytes32 public constant override ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    /// @inheritdoc IPAUAdministeredAgentFactory
    string public constant override VERSION = "1.0.0";

    constructor(IPAUFactoryLike _pauFactory, IAdministeredAgentFactoryLike _administeredAgentFactory) {
        pauFactory = _pauFactory;
        administeredAgentFactory = _administeredAgentFactory;
    }

    //TODO: Should we rename admin to `globalAdmin` or to `subproxy`?
    //     - Thought is that it could be confusing with the other
    //     -`adminConfig` since `admin` is on the entire system.
    /// @inheritdoc IPAUAdministeredAgentFactory
    function deploy(
        address admin,
        bytes32[] memory integrationIds,
        AdminConfig memory adminConfig,
        AdministeredAgentConfig memory administeredAgentConfig
    )
        external
        override
        returns(
            IAccessControlsLike accessControls,
            IControllerLike controller,
            IALMProxyLike proxy,
            IRateLimitsLike rateLimits,
            IAdministeredAgentLike agent
        ) {

        // Step 1: Deploy AccessControls, Proxy, RateLimits, and Controller
        accessControls = IAccessControlsLike(pauFactory.deployAccessControls(address(this)));
        proxy          = IALMProxyLike(pauFactory.deployProxy(address(this)));
        rateLimits     = IRateLimitsLike(pauFactory.deployRateLimits(address(this)));
        controller     = IControllerLike(pauFactory.deployController(address(accessControls), address(proxy), address(rateLimits)));

        // Step 2: Deploy AdministeredAgent with [actors, grantors, revokers]
        agent = IAdministeredAgentLike(administeredAgentFactory.deploy(address(this)));

        for (uint256 i = 0; i < administeredAgentConfig.actors.length; i++) {
            agent.addActor(administeredAgentConfig.actors[i]);
        }

        for (uint256 i = 0; i < administeredAgentConfig.grantors.length; i++) {
            agent.addGrantor(administeredAgentConfig.grantors[i]);
        }

        for (uint256 i = 0; i < administeredAgentConfig.revokers.length; i++) {
            agent.addRevoker(administeredAgentConfig.revokers[i]);
        }

        // Step 3: Grant roles to Proxy, RateLimits, Controller, and AdministeredAgent
        proxy.grantRole(proxy.CONTROLLER(),      address(controller));
        rateLimits.grantRole(proxy.CONTROLLER(), address(controller));

        proxy.grantRole(_DEFAULT_ADMIN_ROLE, admin);
        for (uint256 i = 0; i < adminConfig.proxyAdmins.length; i++) {
            proxy.grantRole(_DEFAULT_ADMIN_ROLE, adminConfig.proxyAdmins[i]);
        }

        rateLimits.grantRole(_DEFAULT_ADMIN_ROLE, admin);
        for (uint256 i = 0; i < adminConfig.rateLimitsAdmins.length; i++) {
            rateLimits.grantRole(_DEFAULT_ADMIN_ROLE, adminConfig.rateLimitsAdmins[i]);
        }

        accessControls.grantRole(_DEFAULT_ADMIN_ROLE, admin);
        for (uint256 i = 0; i < adminConfig.controllerAdmins.length; i++) {
            accessControls.grantRole(_DEFAULT_ADMIN_ROLE, adminConfig.controllerAdmins[i]);
        }

        agent.addAdmin(admin);
        for (uint256 i = 0; i < adminConfig.administeredAgentAdmins.length; i++) {
            agent.addAdmin(adminConfig.administeredAgentAdmins[i]);
        }

        accessControls.grantRole(ALLOCATOR_ROLE, address(agent));

        //Step 4: Update Integrations on Controller
        IControllerLike(controller).updateIntegrations(integrationIds);

        //Step 5: Revoke Roles for Factory
        proxy.revokeRole(_DEFAULT_ADMIN_ROLE,      address(this));
        rateLimits.revokeRole(_DEFAULT_ADMIN_ROLE, address(this));
        accessControls.revokeRole(_DEFAULT_ADMIN_ROLE, address(this));
        agent.removeAdmin(address(this));

        emit PAUAdministeredAgentFactoryDeploy(
            admin,
            address(accessControls),
            address(controller),
            address(proxy),
            address(rateLimits),
            address(agent),
            integrationIds,
            adminConfig,
            administeredAgentConfig
        );

    }

}
