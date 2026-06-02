// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

/**
 * @title  IPAUAdministeredAgentFactory
 * @notice External interface for the {PAUAdministeredAgentFactory}, a one-shot helper
 *         that deploys and wires together a full PAU stack (AccessControls, ALMProxy,
 *         RateLimits, Controller) plus an AdministeredAgent atop an underlying PAU factory,
 *         registers integrations, configures the agent, and hands all admin rights to the
 *         caller-supplied admin while renouncing its own.
 * @dev    All deployed contracts are returned as plain addresses; callers cast them to the
 *         relevant component interfaces as needed.
 */
interface IPAUAdministeredAgentFactory {

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when the supplied PAU factory is the zero address.
    error ZeroPAUFactory();

    /// @notice Thrown when the supplied AdministeredAgent factory is the zero address.
    error ZeroAdministeredAgentFactory();

    /// @notice Thrown when the primary `admin` passed to {deploy} is the zero address.
    error ZeroAdmin();

    /// @notice Thrown when a `roleAdminConfig` entry targets `DEFAULT_ADMIN_ROLE`. Reassigning its
    ///         admin would prevent the factory from renouncing its own admin and brick the deploy.
    error CannotReassignDefaultAdminRole();

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    /**
     * @notice Additional admins to be granted admin rights on each component of the deployed stack, on
     *         top of the system-wide `admin`. The factory always grants `admin` admin rights on every
     *         component, so `admin` must NOT be repeated here: listing it in `administeredAgentAdmins`
     *         reverts (`AlreadyAdmin`), and in the other arrays it is a redundant no-op.
     * @param  accessControlAdmins     Extra admins for the AccessControls contract.
     * @param  proxyAdmins             Extra admins for the ALMProxy contract.
     * @param  rateLimitsAdmins        Extra admins for the RateLimits contract.
     * @param  administeredAgentAdmins Extra admins for the AdministeredAgent.
     */
    struct AdminConfig {
        address[] accessControlAdmins;
        address[] proxyAdmins;
        address[] rateLimitsAdmins;
        address[] administeredAgentAdmins;
    }

    /**
     * @notice A single role -> role-admin assignment applied to the deployed AccessControls
     *         contract via `setRoleAdmin`.
     * @param  role      The role whose admin is being (re)assigned.
     * @param  adminRole The role that will administer `role`.
     */
    struct AccessControlRoleAdminConfig {
        bytes32 role;
        bytes32 adminRole;
    }

    /**
     * @notice Bundle of the contracts produced by a deploy, passed between the factory's internal
     *         steps as a single memory reference (largely to keep the deploy flow under the EVM
     *         stack limit).
     * @param  accessControls The deployed AccessControls contract.
     * @param  controller     The deployed Controller contract.
     * @param  proxy          The deployed ALMProxy contract.
     * @param  rateLimits     The deployed RateLimits contract.
     * @param  agent          The deployed AdministeredAgent contract.
     */
    struct DeployResult {
        address accessControls;
        address controller;
        address proxy;
        address rateLimits;
        address agent;
    }

    /**
     * @notice Configuration applied to the AdministeredAgent after deployment.
     * @param  actors   Addresses to configure as actors on the agent.
     * @param  grantors Addresses authorised to grant roles on the agent.
     * @param  revokers Addresses authorised to revoke roles on the agent.
     */
    struct AdministeredAgentConfig {
        address[] actors;
        address[] grantors;
        address[] revokers;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted once a full PAU stack and AdministeredAgent have been deployed and configured.
     * @param  admin                    The address granted the default admin role on the deployed contracts.
     * @param  freezableProxy           Whether the deployed ALMProxy is the freezable variant.
     * @param  accessControls           The deployed AccessControls contract.
     * @param  controller               The deployed Controller contract.
     * @param  proxy                    The deployed ALMProxy contract.
     * @param  rateLimits               The deployed RateLimits contract.
     * @param  administeredAgent        The deployed AdministeredAgent contract.
     * @param  freezers                 The freezers granted FREEZER_ROLE on the proxy (empty unless freezable).
     * @param  integrationIds           The integration ids registered on the Controller (empty if none).
     * @param  adminConfig              The admin configuration applied across the stack.
     * @param  administeredAgentConfig  The configuration applied to the AdministeredAgent.
     * @param  roleAdminConfig          The role-admin assignments applied to AccessControls.
     */
    event PAUAdministeredAgentFactoryDeploy(
        address indexed admin,
        bool freezableProxy,
        address accessControls,
        address controller,
        address proxy,
        address rateLimits,
        address administeredAgent,
        address[] freezers,
        bytes32[] integrationIds,
        AdminConfig adminConfig,
        AdministeredAgentConfig administeredAgentConfig,
        AccessControlRoleAdminConfig[] roleAdminConfig
    );

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice The allocator role granted to the AdministeredAgent on the AccessControls contract.
     * @return The ALLOCATOR_ROLE identifier.
     */
    function ALLOCATOR_ROLE() external pure returns (bytes32);

    /**
     * @notice Semantic version of this factory implementation.
     * @return The version string.
     */
    function VERSION() external view returns (string memory);

    /**
     * @notice The underlying PAU factory used to deploy each individual component.
     * @return The address of the PAU factory.
     */
    function pauFactory() external view returns (address);

    /**
     * @notice The factory used to deploy the AdministeredAgent.
     * @return The address of the AdministeredAgent factory.
     */
    function administeredAgentFactory() external view returns (address);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Deploys a full PAU stack with a *standard* ALMProxy plus an AdministeredAgent in a
     *         single transaction, wires up roles, registers integrations on the Controller,
     *         configures the AdministeredAgent with the supplied actors/grantors/revokers, applies
     *         any AccessControls role-admin reassignments, and transfers admin rights from this
     *         factory to `admin` (and any extra admins in `adminConfig`).
     * @dev    Emits {PAUAdministeredAgentFactoryDeploy} on completion. After this call, this
     *         factory holds no privileged roles on any of the returned contracts. The Controller is
     *         granted CONTROLLER on the proxy (the role that gates `doCall` for a standard proxy).
     *
     *         Notes:
     *         - When `integrationIds` is empty, the Controller `updateIntegrations` call is
     *           skipped entirely (the Controller reverts on an empty array), so a stack can be
     *           deployed with no integrations and configured later by an admin.
     *         - `roleAdminConfig` entries are applied while this factory still holds
     *           DEFAULT_ADMIN_ROLE on AccessControls. Targeting `DEFAULT_ADMIN_ROLE` is rejected with
     *           `CannotReassignDefaultAdminRole`, since reassigning its admin would prevent the
     *           factory from renouncing its own admin.
     * @param  admin                   System-wide admin, granted admin rights on every deployed component
     *                                 (AccessControls, ALMProxy, RateLimits, AdministeredAgent). Must not
     *                                 be repeated in `adminConfig` (see {AdminConfig}).
     * @param  integrationIds          Integration ids to register on the Controller via `updateIntegrations` (may be empty).
     * @param  adminConfig             Additional admins to grant across the deployed stack.
     * @param  administeredAgentConfig Actor/grantor/revoker configuration for the AdministeredAgent.
     * @param  roleAdminConfig         Role-admin assignments to apply to the AccessControls contract.
     * @return accessControls          The deployed AccessControls contract.
     * @return controller              The deployed Controller contract.
     * @return proxy                   The deployed ALMProxy contract.
     * @return rateLimits              The deployed RateLimits contract.
     * @return agent                   The deployed AdministeredAgent contract.
     */
    function deploy(
        address admin,
        bytes32[] calldata integrationIds,
        AdminConfig calldata adminConfig,
        AdministeredAgentConfig calldata administeredAgentConfig,
        AccessControlRoleAdminConfig[] calldata roleAdminConfig
    )
        external
        returns (
            address accessControls,
            address controller,
            address proxy,
            address rateLimits,
            address agent
        );

    /**
     * @notice Identical to {deploy} but deploys the *freezable* ALMProxy variant and grants
     *         FREEZER_ROLE on it to each address in `freezers`.
     * @dev    Emits {PAUAdministeredAgentFactoryDeploy} on completion. The Controller is granted
     *         ALLOCATOR_ROLE on the proxy (the role that gates `doCall` for a freezable proxy)
     *         rather than CONTROLLER. See {deploy} for the shared `integrationIds`/`roleAdminConfig`
     *         notes.
     * @param  admin                   System-wide admin, granted admin rights on every deployed component
     *                                 (AccessControls, ALMProxy, RateLimits, AdministeredAgent). Must not
     *                                 be repeated in `adminConfig` (see {AdminConfig}).
     * @param  freezers                Addresses granted FREEZER_ROLE on the freezable ALMProxy.
     * @param  integrationIds          Integration ids to register on the Controller via `updateIntegrations` (may be empty).
     * @param  adminConfig             Additional admins to grant across the deployed stack.
     * @param  administeredAgentConfig Actor/grantor/revoker configuration for the AdministeredAgent.
     * @param  roleAdminConfig         Role-admin assignments to apply to the AccessControls contract.
     * @return accessControls          The deployed AccessControls contract.
     * @return controller              The deployed Controller contract.
     * @return proxy                   The deployed (freezable) ALMProxy contract.
     * @return rateLimits              The deployed RateLimits contract.
     * @return agent                   The deployed AdministeredAgent contract.
     */
    function deployFreezable(
        address admin,
        address[] calldata freezers,
        bytes32[] calldata integrationIds,
        AdminConfig calldata adminConfig,
        AdministeredAgentConfig calldata administeredAgentConfig,
        AccessControlRoleAdminConfig[] calldata roleAdminConfig
    )
        external
        returns (
            address accessControls,
            address controller,
            address proxy,
            address rateLimits,
            address agent
        );

}
