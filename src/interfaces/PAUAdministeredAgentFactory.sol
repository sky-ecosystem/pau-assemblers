// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IPAUFactoryLike,
    IAdministeredAgentFactoryLike,
    IRateLimitsLike,
    IALMProxyLike,
    IAccessControlsLike,
    IControllerLike,
    IAdministeredAgentLike
} from "../PAUAdministeredAgentFactory.sol";

/**
 * @title  IPAUAdministeredAgentFactory
 * @notice External interface for the {PAUAdministeredAgentFactory}, a one-shot helper
 *         that deploys and wires together a full PAU stack (AccessControls, ALMProxy,
 *         RateLimits, Controller) plus an AdministeredAgent atop an underlying
 *         {IPAUFactoryLike}, registers integrations, configures the agent, and hands
 *         all admin rights to the caller-supplied admin while renouncing its own.
 */
interface IPAUAdministeredAgentFactory {

    /**
     * @notice Admin addresses to be granted the default admin role on each
     *         component of the deployed stack, in addition to the primary `admin`.
     * @param  controllerAdmins        Extra admins for the AccessControls contract.
     * @param  proxyAdmins             Extra admins for the ALMProxy contract.
     * @param  rateLimitsAdmins        Extra admins for the RateLimits contract.
     * @param  administeredAgentAdmins Extra admins for the AdministeredAgent.
     */
    struct AdminConfig {
        address[] controllerAdmins;
        address[] proxyAdmins;
        address[] rateLimitsAdmins;
        address[] administeredAgentAdmins;
    }

    /**
     * @notice Configuration applied to the AdministeredAgent after deployment.
     * @param  ids      Integration ids associated with the agent.
     * @param  actors   Addresses to configure as actors on the agent.
     * @param  grantors Addresses authorised to grant roles on the agent.
     * @param  revokers Addresses authorised to revoke roles on the agent.
     */
    struct AdministeredAgentConfig {
        bytes32[] ids;
        address[] actors;
        address[] grantors;
        address[] revokers;
    }

    /**
     * @notice Emitted once a full PAU stack and AdministeredAgent have been deployed and configured.
     * @param  admin                    The address granted the default admin role on the deployed contracts.
     * @param  accessControls           The deployed AccessControls contract.
     * @param  controller               The deployed Controller contract.
     * @param  proxy                    The deployed ALMProxy contract.
     * @param  rateLimits               The deployed RateLimits contract.
     * @param  administeredAgent        The deployed AdministeredAgent contract.
     * @param  integrationIds           The integration ids registered on the Controller.
     * @param  adminConfig              The admin configuration applied across the stack.
     * @param  administeredAgentConfig  The configuration applied to the AdministeredAgent.
     */
    event PAUAdministeredAgentFactoryDeploy(
        address indexed admin,
        address accessControls,
        address controller,
        address proxy,
        address rateLimits,
        address administeredAgent,
        bytes32[] integrationIds,
        AdminConfig adminConfig,
        AdministeredAgentConfig administeredAgentConfig
    );

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
     * @return The IPAUFactoryLike-compatible factory.
     */
    function pauFactory() external view returns (IPAUFactoryLike);

    /**
     * @notice The factory used to deploy the AdministeredAgent.
     * @return The IAdministeredAgentFactoryLike-compatible factory.
     */
    function administeredAgentFactory() external view returns (IAdministeredAgentFactoryLike);

    /**
     * @notice Deploys a full PAU stack plus an AdministeredAgent in a single transaction,
     *         wires up roles, registers integrations on the Controller, configures the
     *         AdministeredAgent with the supplied actors/grantors/revokers, and transfers
     *         admin rights from this factory to `admin` (and any extra admins in `adminConfig`).
     * @dev    Emits {PAUAdministeredAgentFactoryDeploy} on completion. After this call, this
     *         factory holds no privileged roles on any of the returned contracts.
     * @param  admin                   Address that will receive the default admin role on the deployed contracts.
     * @param  integrationIds          Integration ids to register on the Controller via `updateIntegrations`.
     * @param  adminConfig             Additional admins to grant across the deployed stack.
     * @param  administeredAgentConfig Actor/grantor/revoker configuration for the AdministeredAgent.
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
        AdministeredAgentConfig calldata administeredAgentConfig
    )
        external
        returns (
            IAccessControlsLike accessControls,
            IControllerLike controller,
            IALMProxyLike proxy,
            IRateLimitsLike rateLimits,
            IAdministeredAgentLike agent
        );

}
