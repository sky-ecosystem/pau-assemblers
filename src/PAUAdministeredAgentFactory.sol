// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IPAUAdministeredAgentFactory } from "./interfaces/PAUAdministeredAgentFactory.sol";

interface IPAUFactoryLike {

    function deployAccessControls(address admin) external returns(address accessControls);

    function deployController(address accessControls, address proxy, address rateLimits)
            external
            returns (address controller);

    function deployALMProxy(address admin) external returns (address almProxy);

    function deployALMProxyFreezable(address admin) external returns (address almProxyFreezable);

    function deployRateLimits(address admin) external returns (address rateLimits);

}

interface IAdministeredAgentFactoryLike {

    function deploy(address admin) external returns(address);

}

interface IRoleGrantable {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

}

interface IRateLimitsLike is IRoleGrantable {}

interface IALMProxyLike is IRoleGrantable {}

interface IAccessControlsLike is IRoleGrantable {

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;

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
 *         its own. {deploy} wires a standard ALMProxy; {deployFreezable} wires the
 *         freezable variant and additionally configures its freezers.
 */
contract PAUAdministeredAgentFactory is IPAUAdministeredAgentFactory {

    /// @inheritdoc IPAUAdministeredAgentFactory
    IPAUFactoryLike public immutable override pauFactory;

    /// @inheritdoc IPAUAdministeredAgentFactory
    IAdministeredAgentFactoryLike public immutable override administeredAgentFactory;

    bytes32 internal constant _DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 internal constant _CONTROLLER_ROLE = keccak256("CONTROLLER");

    bytes32 internal constant _FREEZER_ROLE = keccak256("FREEZER_ROLE");

    /// @inheritdoc IPAUAdministeredAgentFactory
    bytes32 public constant override ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    /// @inheritdoc IPAUAdministeredAgentFactory
    string public constant override VERSION = "1.0.0";

    constructor(IPAUFactoryLike _pauFactory, IAdministeredAgentFactoryLike _administeredAgentFactory) {
        require(address(_pauFactory)               != address(0), ZeroPAUFactory());
        require(address(_administeredAgentFactory) != address(0), ZeroAdministeredAgentFactory());

        pauFactory               = _pauFactory;
        administeredAgentFactory = _administeredAgentFactory;
    }

    /**********************************************************************************************/
    /*** External Interactive Functions                                                         ***/
    /**********************************************************************************************/

    //TODO: Should we rename admin to `globalAdmin` or to `subproxy`?
    //     - Thought is that it could be confusing with the other
    //     -`adminConfig` since `admin` is on the entire system.
    /// @inheritdoc IPAUAdministeredAgentFactory
    function deploy(
        address admin,
        bytes32[] memory integrationIds,
        AdminConfig memory adminConfig,
        AdministeredAgentConfig memory administeredAgentConfig,
        AccessControlRoleAdminConfig[] memory roleAdminConfig
    )
        external
        override
        returns (
            IAccessControlsLike accessControls,
            IControllerLike controller,
            IALMProxyLike proxy,
            IRateLimitsLike rateLimits,
            IAdministeredAgentLike agent
        )
    {
        return _deploy(
            admin,
            false,
            new address[](0),
            integrationIds,
            adminConfig,
            administeredAgentConfig,
            roleAdminConfig
        );
    }

    /// @inheritdoc IPAUAdministeredAgentFactory
    function deployFreezable(
        address admin,
        address[] memory freezers,
        bytes32[] memory integrationIds,
        AdminConfig memory adminConfig,
        AdministeredAgentConfig memory administeredAgentConfig,
        AccessControlRoleAdminConfig[] memory roleAdminConfig
    )
        external
        override
        returns (
            IAccessControlsLike accessControls,
            IControllerLike controller,
            IALMProxyLike proxy,
            IRateLimitsLike rateLimits,
            IAdministeredAgentLike agent
        )
    {
        return _deploy(
            admin,
            true,
            freezers,
            integrationIds,
            adminConfig,
            administeredAgentConfig,
            roleAdminConfig
        );
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _deploy(
        address admin,
        bool freezableProxy,
        address[] memory freezers,
        bytes32[] memory integrationIds,
        AdminConfig memory adminConfig,
        AdministeredAgentConfig memory administeredAgentConfig,
        AccessControlRoleAdminConfig[] memory roleAdminConfig
    )
        private
        returns (
            IAccessControlsLike,
            IControllerLike,
            IALMProxyLike,
            IRateLimitsLike,
            IAdministeredAgentLike
        )
    {
        require(admin != address(0), ZeroAdmin());

        // Step 1: Deploy AccessControls, Proxy (standard or freezable), RateLimits, Controller, Agent.
        DeployResult memory d = _deployStack(freezableProxy);

        // Step 2: Configure the AdministeredAgent with [actors, grantors, revokers].
        _configureAgent(d.agent, administeredAgentConfig);

        // Step 3: Wire roles across the stack (incl. freezers when freezable).
        _grantRoles(d, admin, freezableProxy, freezers, adminConfig);

        // Step 4: Register integrations (skipped when none supplied).
        _registerIntegrations(d.controller, integrationIds);

        // Step 5: Apply AccessControls role-admin reconfiguration while still holding admin.
        _applyRoleAdmins(d.accessControls, roleAdminConfig);

        // Step 6: Renounce every role this factory held during bootstrap.
        _renounce(d);

        _emitDeploy(d, admin, freezableProxy, freezers, integrationIds, adminConfig, administeredAgentConfig, roleAdminConfig);

        return (d.accessControls, d.controller, d.proxy, d.rateLimits, d.agent);
    }

    function _deployStack(bool freezableProxy) private returns (DeployResult memory d) {
        d.accessControls = IAccessControlsLike(pauFactory.deployAccessControls(address(this)));
        d.proxy          = IALMProxyLike(
            freezableProxy
                ? pauFactory.deployALMProxyFreezable(address(this))
                : pauFactory.deployALMProxy(address(this))
        );
        d.rateLimits     = IRateLimitsLike(pauFactory.deployRateLimits(address(this)));
        d.controller     = IControllerLike(
            pauFactory.deployController(address(d.accessControls), address(d.proxy), address(d.rateLimits))
        );
        d.agent          = IAdministeredAgentLike(administeredAgentFactory.deploy(address(this)));
    }

    function _configureAgent(IAdministeredAgentLike agent, AdministeredAgentConfig memory cfg) private {
        for (uint256 i = 0; i < cfg.actors.length; i++) {
            agent.addActor(cfg.actors[i]);
        }
        for (uint256 i = 0; i < cfg.grantors.length; i++) {
            agent.addGrantor(cfg.grantors[i]);
        }
        for (uint256 i = 0; i < cfg.revokers.length; i++) {
            agent.addRevoker(cfg.revokers[i]);
        }
    }

    function _grantRoles(
        DeployResult memory d,
        address admin,
        bool freezableProxy,
        address[] memory freezers,
        AdminConfig memory adminConfig
    )
        private
    {
        // The Controller routes calls through the proxy: a standard ALMProxy gates `doCall` on
        // CONTROLLER, a freezable ALMProxy gates it on ALLOCATOR_ROLE. RateLimits always uses
        // CONTROLLER.
        d.proxy.grantRole(freezableProxy ? ALLOCATOR_ROLE : _CONTROLLER_ROLE, address(d.controller));
        d.rateLimits.grantRole(_CONTROLLER_ROLE, address(d.controller));

        // Freezers can remove the allocator on a freezable proxy (no-op list for a standard proxy).
        for (uint256 i = 0; i < freezers.length; i++) {
            d.proxy.grantRole(_FREEZER_ROLE, freezers[i]);
        }

        // DEFAULT_ADMIN_ROLE to `admin` plus any extras, on each component.
        _grantDefaultAdmins(address(d.proxy),          admin, adminConfig.proxyAdmins);
        _grantDefaultAdmins(address(d.rateLimits),     admin, adminConfig.rateLimitsAdmins);
        _grantDefaultAdmins(address(d.accessControls), admin, adminConfig.controllerAdmins);

        // Admins on the AdministeredAgent.
        d.agent.addAdmin(admin);
        for (uint256 i = 0; i < adminConfig.administeredAgentAdmins.length; i++) {
            d.agent.addAdmin(adminConfig.administeredAgentAdmins[i]);
        }

        // The AdministeredAgent is the allocator on AccessControls.
        d.accessControls.grantRole(ALLOCATOR_ROLE, address(d.agent));
    }

    function _grantDefaultAdmins(address target, address admin, address[] memory extra) private {
        IRoleGrantable(target).grantRole(_DEFAULT_ADMIN_ROLE, admin);
        for (uint256 i = 0; i < extra.length; i++) {
            IRoleGrantable(target).grantRole(_DEFAULT_ADMIN_ROLE, extra[i]);
        }
    }

    function _registerIntegrations(IControllerLike controller, bytes32[] memory integrationIds) private {
        // Controller.updateIntegrations reverts on an empty array, so skip the call when none given.
        if (integrationIds.length > 0) {
            controller.updateIntegrations(integrationIds);
        }
    }

    function _applyRoleAdmins(
        IAccessControlsLike accessControls,
        AccessControlRoleAdminConfig[] memory roleAdminConfig
    )
        private
    {
        for (uint256 i = 0; i < roleAdminConfig.length; i++) {
            accessControls.setRoleAdmin(roleAdminConfig[i].role, roleAdminConfig[i].adminRole);
        }
    }

    function _renounce(DeployResult memory d) private {
        d.proxy.revokeRole(_DEFAULT_ADMIN_ROLE,          address(this));
        d.rateLimits.revokeRole(_DEFAULT_ADMIN_ROLE,     address(this));
        d.accessControls.revokeRole(_DEFAULT_ADMIN_ROLE, address(this));
        d.agent.removeAdmin(address(this));
    }

    /// @dev Emits {PAUAdministeredAgentFactoryDeploy} in its own frame to keep the deploy flow
    ///      under the stack limit (the event packs five addresses plus several dynamic payloads).
    function _emitDeploy(
        DeployResult memory d,
        address admin,
        bool freezableProxy,
        address[] memory freezers,
        bytes32[] memory integrationIds,
        AdminConfig memory adminConfig,
        AdministeredAgentConfig memory administeredAgentConfig,
        AccessControlRoleAdminConfig[] memory roleAdminConfig
    )
        private
    {
        emit PAUAdministeredAgentFactoryDeploy(
            admin,
            freezableProxy,
            address(d.accessControls),
            address(d.controller),
            address(d.proxy),
            address(d.rateLimits),
            address(d.agent),
            freezers,
            integrationIds,
            adminConfig,
            administeredAgentConfig,
            roleAdminConfig
        );
    }

}
