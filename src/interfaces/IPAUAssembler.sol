// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

/**
 * @title  IPAUAssembler
 * @notice External interface for the {PAUAssembler}, a one-shot helper that deploys and configures
 *         one or more PAU stacks sharing a single ALMProxy, in a single transaction. It deploys the
 *         shared ALMProxy, a set of AccessControls and RateLimits (each addressable by a caller
 *         supplied id), then wires each Controller to a referenced AccessControls/RateLimits pair,
 *         syncs its integrations, and grants each allocator AdministeredAgent the allocator role on
 *         its referenced AccessControls.
 * @dev    All deployed contracts are returned as plain addresses; callers cast them to the relevant
 *         component interfaces as needed. The `id` fields are scoped to a single `deploy` call and
 *         are only used to cross-reference components within that call.
 */
interface IPAUAssembler {

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when an admin array for an AdministeredAgent is empty.
    error NoAgentAdmins();

    /// @notice Thrown when an admin array for a component's default admins is empty.
    error NoDefaultAdmins();

    /// @notice Thrown when the supplied PAU factory is the zero address.
    error ZeroPAUFactory();

    /// @notice Thrown when the supplied AdministeredAgent factory is the zero address.
    error ZeroAdministeredAgentFactory();

    /// @notice Thrown when a supplied default admin address is the zero address.
    error ZeroDefaultAdmin();

    /// @notice Thrown when two AccessControlsConfigs share the same `id`.
    error DuplicateAccessControlsId(bytes32 id);

    /// @notice Thrown when two RateLimitConfigs share the same `id`.
    error DuplicateRateLimitsId(bytes32 id);

    /// @notice Thrown when a ControllerConfig or AdministeredAgentConfig references an unknown
    ///         AccessControls `id`.
    error InvalidAccessControlsId(bytes32 id);

    /// @notice Thrown when a ControllerConfig references an unknown RateLimits `id`.
    error InvalidRateLimitsId(bytes32 id);

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    /**
     * @notice Configuration for a Controller deployed against the shared ALMProxy.
     * @param  integrationIds  Integration IDs to sync on the Controller (may be empty).
     * @param  rateLimitId     The `id` of the RateLimits this Controller is wired to.
     * @param  accessControlsId The `id` of the AccessControls this Controller is wired to.
     */
    struct ControllerConfig {
        bytes32[] integrationIds;
        bytes32   rateLimitId;
        bytes32   accessControlsId;
    }

    /**
     * @notice Configuration for a RateLimits contract.
     * @param  id     Identifier used to reference this RateLimits from a ControllerConfig.
     * @param  admins Default admins for the RateLimits contract.
     */
    struct RateLimitConfig {
        bytes32   id;
        address[] admins;
    }

    /**
     * @notice Configuration for an AccessControls contract.
     * @param  id     Identifier used to reference this AccessControls from a ControllerConfig or
     *                AdministeredAgentConfig.
     * @param  admins Default admins for the AccessControls contract.
     */
    struct AccessControlsConfig {
        bytes32   id;
        address[] admins;
    }

    /**
     * @notice Configuration for the shared ALMProxy.
     * @param  admins Default admins for the ALMProxy contract.
     */
    struct ALMProxyConfig {
        address[] admins;
    }

    /**
     * @notice Configuration applied to an allocator AdministeredAgent after deployment.
     * @param  accessControlsId The `id` of the AccessControls this agent is granted the allocator
     *                         role on.
     * @param  admins          Addresses to configure as admins on the agent.
     * @param  actors          Addresses to configure as actors on the agent.
     * @param  grantors        Addresses to configure as grantors on the agent.
     * @param  revokers        Addresses to configure as revokers on the agent.
     */
    struct AdministeredAgentConfig {
        bytes32   accessControlsId;
        address[] admins;
        address[] actors;
        address[] grantors;
        address[] revokers;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted once the PAU stacks and allocator AdministeredAgents have been deployed and
     *         configured.
     * @param  proxy                 The deployed shared ALMProxy contract.
     * @param  controllers           The deployed Controller contracts.
     * @param  accessControls        The deployed AccessControls contracts.
     * @param  rateLimits            The deployed RateLimits contracts.
     * @param  allocatorAgents       The deployed allocators as AdministeredAgent contracts.
     * @param  controllerConfigs     The configurations applied to each Controller.
     * @param  rateLimitConfigs      The configurations applied to each RateLimits.
     * @param  accessControlsConfigs  The configurations applied to each AccessControls.
     * @param  allocatorAgentConfigs The configurations applied to each allocator AdministeredAgent.
     * @param  almProxyConfig        The configuration applied to the shared ALMProxy.
     */
    event Deployment(
        address                   indexed proxy,
        address[]                         controllers,
        address[]                         accessControls,
        address[]                         rateLimits,
        address[]                         allocatorAgents,
        ControllerConfig[]                controllerConfigs,
        RateLimitConfig[]                 rateLimitConfigs,
        AccessControlsConfig[]            accessControlsConfigs,
        AdministeredAgentConfig[]         allocatorAgentConfigs,
        ALMProxyConfig                    almProxyConfig
    );

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Semantic version of this assembler implementation.
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
     * @notice Deploys and configures one or more PAU stacks sharing a single ALMProxy, with
     *         allocators as AdministeredAgent contracts, in a single transaction. Wires each
     *         Controller to its referenced AccessControls/RateLimits pair, syncs integrations, and
     *         grants each allocator the allocator role on its referenced AccessControls.
     * @dev    Emits {Deployment} on completion. After this call, this assembler holds no privileged
     *         roles on any of the returned contracts. Each Controller is granted CONTROLLER on the
     *         shared ALMProxy and on its referenced RateLimits.
     *
     *         Notes:
     *         - AccessControls and RateLimits are cross-referenced by their `id` via transient
     *           storage scoped to this call; ids must be unique within their respective sets.
     *         - When a ControllerConfig's `integrationIds` is empty, its `updateIntegrations` call
     *           is skipped (the Controller reverts on an empty array).
     * @param  controllerConfigs     Configuration for each Controller.
     * @param  rateLimitConfigs      Configuration for each RateLimits.
     * @param  accessControlsConfigs  Configuration for each AccessControls.
     * @param  allocatorAgentConfigs Configuration for each allocator AdministeredAgent.
     * @param  almProxyConfig        Configuration for the shared ALMProxy.
     * @return proxy                 The deployed shared ALMProxy contract.
     * @return controllers           The deployed Controller contracts.
     * @return accessControls        The deployed AccessControls contracts.
     * @return rateLimits            The deployed RateLimits contracts.
     * @return allocatorAgents       The deployed allocator AdministeredAgent contracts.
     */
    function deploy(
        ControllerConfig[]        memory controllerConfigs,
        RateLimitConfig[]         memory rateLimitConfigs,
        AccessControlsConfig[]    memory accessControlsConfigs,
        AdministeredAgentConfig[] memory allocatorAgentConfigs,
        ALMProxyConfig            memory almProxyConfig
    )
        external
        returns (
            address          proxy,
            address[] memory controllers,
            address[] memory accessControls,
            address[] memory rateLimits,
            address[] memory allocatorAgents
        );

}
