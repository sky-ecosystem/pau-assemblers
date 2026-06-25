// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IPAUAssembler } from "./IPAUAssembler.sol";

/**
 * @title  IDefaultNFATAssembler
 * @notice External interface for the {DefaultNFATAssembler}, a one-shot helper that deploys a full
 *         PAU stack via the {PAUAssembler} and then deploys an NFAT facility wired to the resulting
 *         shared ALMProxy, in a single transaction.
 * @dev    All deployed contracts are returned as plain addresses; callers cast them to the relevant
 *         component interfaces as needed. The NFAT facility's recipient and sole bud are both fixed
 *         to the deployed ALMProxy.
 */
interface IDefaultNFATAssembler {

    /**********************************************************************************************/
    /*** Custom Errors                                                                          ***/
    /**********************************************************************************************/

    /// @notice Thrown when the supplied PAUAssembler is the zero address.
    error ZeroPAUAssembler();

    /// @notice Thrown when the supplied NFAT factory is the zero address.
    error ZeroNFATFactory();

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    /**
     * @notice The full set of {PAUAssembler} configuration arrays forwarded to its `deploy` call.
     * @param  controllerConfigs     Configuration for each Controller.
     * @param  rateLimitConfigs      Configuration for each RateLimits.
     * @param  accessControlConfigs  Configuration for each AccessControls.
     * @param  allocatorAgentConfigs Configuration for each allocator AdministeredAgent.
     * @param  almProxyConfig        Configuration for the shared ALMProxy.
     */
    struct PAUAssemblerInput {
        IPAUAssembler.ControllerConfig[]        controllerConfigs;
        IPAUAssembler.RateLimitConfig[]         rateLimitConfigs;
        IPAUAssembler.AccessControlConfig[]     accessControlConfigs;
        IPAUAssembler.AdministeredAgentConfig[] allocatorAgentConfigs;
        IPAUAssembler.ALMProxyConfig            almProxyConfig;
    }

    /**
     * @notice Parameters forwarded to the NFAT factory. The facility's recipient and sole bud are
     *         fixed to the deployed ALMProxy, so neither is supplied here.
     * @param  name            The NFAT name.
     * @param  symbol          The NFAT symbol.
     * @param  baseURI         The NFAT base URI.
     * @param  gem             The gem token backing the facility.
     * @param  identityNetwork The identity network used by the facility.
     * @param  cops            Cops for the facility.
     * @param  wards           Wards for the facility.
     */
    struct NFATFactoryInput {
        string    name;
        string    symbol;
        string    baseURI;
        address   gem;
        address   identityNetwork;
        address[] wards;
        address[] cops;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted once the PAU stack and NFAT facility have been deployed and configured.
     * @param  proxy             The deployed shared ALMProxy contract.
     * @param  nfatFacility      The deployed NFAT facility contract.
     * @param  controllers       The deployed Controller contracts.
     * @param  accessControls    The deployed AccessControls contracts.
     * @param  rateLimits        The deployed RateLimits contracts.
     * @param  allocatorAgents   The deployed allocators as AdministeredAgent contracts.
     * @param  pauAssemblerInput The configuration forwarded to the {PAUAssembler}.
     * @param  nfatFactoryInput  The configuration forwarded to the NFAT factory.
     */
    event Deployment(
        address           indexed proxy,
        address           indexed nfatFacility,
        address[]                 controllers,
        address[]                 accessControls,
        address[]                 rateLimits,
        address[]                 allocatorAgents,
        PAUAssemblerInput         pauAssemblerInput,
        NFATFactoryInput          nfatFactoryInput
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
     * @notice The PAUAssembler used to deploy and configure the PAU stack.
     * @return The address of the PAUAssembler.
     */
    function pauAssembler() external view returns (address);

    /**
     * @notice The factory used to deploy the NFAT facility.
     * @return The address of the NFAT factory.
     */
    function nfatFactory() external view returns (address);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Deploys a full PAU stack via the {PAUAssembler} and an NFAT facility wired to the
     *         resulting shared ALMProxy, in a single transaction.
     * @dev    Emits {Deployment} on completion. The NFAT facility's recipient and sole bud are both
     *         set to the deployed ALMProxy.
     * @param  pauAssemblerInput The configuration forwarded to the {PAUAssembler}.
     * @param  nfatFactoryInput  The configuration forwarded to the NFAT factory.
     * @return proxy             The deployed shared ALMProxy contract.
     * @return nfatFacility      The deployed NFAT facility contract.
     * @return controllers       The deployed Controller contracts.
     * @return accessControls    The deployed AccessControls contracts.
     * @return rateLimits        The deployed RateLimits contracts.
     * @return allocatorAgents   The deployed allocator AdministeredAgent contracts.
     */
    function deploy(
        PAUAssemblerInput memory pauAssemblerInput,
        NFATFactoryInput  memory nfatFactoryInput
    )
        external
        returns (
            address          proxy,
            address          nfatFacility,
            address[] memory controllers,
            address[] memory accessControls,
            address[] memory rateLimits,
            address[] memory allocatorAgents
        );

}
