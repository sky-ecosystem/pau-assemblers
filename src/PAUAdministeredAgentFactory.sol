// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IPAUAdministeredAgentFactory } from "./interfaces/IPAUAdministeredAgentFactory.sol";

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

interface IRoleGrantableLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

}

interface IRateLimitsLike is IRoleGrantableLike {}

interface IALMProxyLike is IRoleGrantableLike {}

interface IAccessControlsLike is IRoleGrantableLike {

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

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    IPAUFactoryLike               internal immutable _pauFactory;
    IAdministeredAgentFactoryLike internal immutable _administeredAgentFactory;

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 internal constant _CONTROLLER_ROLE = keccak256("CONTROLLER");

    bytes32 internal constant _FREEZER_ROLE = keccak256("FREEZER_ROLE");

    /// @inheritdoc IPAUAdministeredAgentFactory
    bytes32 public constant override ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    /// @inheritdoc IPAUAdministeredAgentFactory
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(IPAUFactoryLike pauFactory_, IAdministeredAgentFactoryLike administeredAgentFactory_) {
        require(address(pauFactory_)               != address(0), ZeroPAUFactory());
        require(address(administeredAgentFactory_) != address(0), ZeroAdministeredAgentFactory());

        _pauFactory               = pauFactory_;
        _administeredAgentFactory = administeredAgentFactory_;
    }

    /**********************************************************************************************/
    /*** External Interactive Functions                                                         ***/
    /**********************************************************************************************/

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
            address accessControls,
            address controller,
            address proxy,
            address rateLimits,
            address agent
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
            address accessControls,
            address controller,
            address proxy,
            address rateLimits,
            address agent
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
    /*** External Variable Getters                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IPAUAdministeredAgentFactory
    function pauFactory() external view override returns (address) {
        return address(_pauFactory);
    }

    /// @inheritdoc IPAUAdministeredAgentFactory
    function administeredAgentFactory() external view override returns (address) {
        return address(_administeredAgentFactory);
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
        internal
        returns (address, address, address, address, address)
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

    function _deployStack(bool freezableProxy) internal returns (DeployResult memory d) {
        d.accessControls = _pauFactory.deployAccessControls(address(this));
        d.proxy          = freezableProxy
            ? _pauFactory.deployALMProxyFreezable(address(this))
            : _pauFactory.deployALMProxy(address(this));
        d.rateLimits     = _pauFactory.deployRateLimits(address(this));
        d.controller     = _pauFactory.deployController(d.accessControls, d.proxy, d.rateLimits);
        d.agent          = _administeredAgentFactory.deploy(address(this));
    }

    function _configureAgent(address agent, AdministeredAgentConfig memory cfg) internal {
        IAdministeredAgentLike a = IAdministeredAgentLike(agent);

        for (uint256 i = 0; i < cfg.actors.length; i++) {
            a.addActor(cfg.actors[i]);
        }
        for (uint256 i = 0; i < cfg.grantors.length; i++) {
            a.addGrantor(cfg.grantors[i]);
        }
        for (uint256 i = 0; i < cfg.revokers.length; i++) {
            a.addRevoker(cfg.revokers[i]);
        }
    }

    function _grantRoles(
        DeployResult memory d,
        address admin,
        bool freezableProxy,
        address[] memory freezers,
        AdminConfig memory adminConfig
    )
        internal
    {
        // The Controller routes calls through the proxy: a standard ALMProxy gates `doCall` on
        // CONTROLLER, a freezable ALMProxy gates it on ALLOCATOR_ROLE. RateLimits always uses
        // CONTROLLER.
        IALMProxyLike(d.proxy).grantRole(freezableProxy ? ALLOCATOR_ROLE : _CONTROLLER_ROLE, d.controller);
        IRateLimitsLike(d.rateLimits).grantRole(_CONTROLLER_ROLE, d.controller);

        // Freezers can remove the allocator on a freezable proxy (no-op list for a standard proxy).
        for (uint256 i = 0; i < freezers.length; i++) {
            IALMProxyLike(d.proxy).grantRole(_FREEZER_ROLE, freezers[i]);
        }

        // DEFAULT_ADMIN_ROLE to `admin` plus any extras, on each component.
        _grantDefaultAdmins(d.proxy,          admin, adminConfig.proxyAdmins);
        _grantDefaultAdmins(d.rateLimits,     admin, adminConfig.rateLimitsAdmins);
        _grantDefaultAdmins(d.accessControls, admin, adminConfig.accessControlAdmins);

        // Admins on the AdministeredAgent.
        IAdministeredAgentLike(d.agent).addAdmin(admin);
        for (uint256 i = 0; i < adminConfig.administeredAgentAdmins.length; i++) {
            IAdministeredAgentLike(d.agent).addAdmin(adminConfig.administeredAgentAdmins[i]);
        }

        // The AdministeredAgent is the allocator on AccessControls.
        IAccessControlsLike(d.accessControls).grantRole(ALLOCATOR_ROLE, d.agent);
    }

    function _grantDefaultAdmins(address target, address admin, address[] memory extra) internal {
        IRoleGrantableLike(target).grantRole(_DEFAULT_ADMIN_ROLE, admin);
        for (uint256 i = 0; i < extra.length; i++) {
            IRoleGrantableLike(target).grantRole(_DEFAULT_ADMIN_ROLE, extra[i]);
        }
    }

    function _registerIntegrations(address controller, bytes32[] memory integrationIds) internal {
        // Controller.updateIntegrations reverts on an empty array, so skip the call when none given.
        if (integrationIds.length > 0) {
            IControllerLike(controller).updateIntegrations(integrationIds);
        }
    }

    function _applyRoleAdmins(
        address accessControls,
        AccessControlRoleAdminConfig[] memory roleAdminConfig
    )
        internal
    {
        for (uint256 i = 0; i < roleAdminConfig.length; i++) {
            IAccessControlsLike(accessControls).setRoleAdmin(roleAdminConfig[i].role, roleAdminConfig[i].adminRole);
        }
    }

    function _renounce(DeployResult memory d) internal {
        IRoleGrantableLike(d.proxy).revokeRole(_DEFAULT_ADMIN_ROLE,          address(this));
        IRoleGrantableLike(d.rateLimits).revokeRole(_DEFAULT_ADMIN_ROLE,     address(this));
        IRoleGrantableLike(d.accessControls).revokeRole(_DEFAULT_ADMIN_ROLE, address(this));
        IAdministeredAgentLike(d.agent).removeAdmin(address(this));
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
        internal
    {
        emit PAUAdministeredAgentFactoryDeploy(
            admin,
            freezableProxy,
            d.accessControls,
            d.controller,
            d.proxy,
            d.rateLimits,
            d.agent,
            freezers,
            integrationIds,
            adminConfig,
            administeredAgentConfig,
            roleAdminConfig
        );
    }

}
