// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IDefaultNFATPAUAssembler } from "./interfaces/IDefaultNFATPAUAssembler.sol";
import { IPAUAssembler }            from "./interfaces/IPAUAssembler.sol";

interface INFATFacilityFactoryLike {

    function deploy(
        string    memory name,
        string    memory symbol,
        string    memory baseURI,
        address          gem,
        address          recipient,
        address          identityNetwork,
        address[] memory wards,
        address[] memory buds,
        address[] memory cops
    ) external returns (address);

}

contract DefaultNFATPAUAssembler is IDefaultNFATPAUAssembler {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IDefaultNFATPAUAssembler
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IDefaultNFATPAUAssembler
    address public immutable nfatFacilityFactory;

    /// @inheritdoc IDefaultNFATPAUAssembler
    address public immutable pauAssembler;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address nfatFacilityFactory_, address pauAssembler_) {
        require(nfatFacilityFactory_ != address(0), ZeroNFATFacilityFactory());
        require(pauAssembler_        != address(0), ZeroPAUAssembler());

        nfatFacilityFactory = nfatFacilityFactory_;
        pauAssembler        = pauAssembler_;
    }

    /**********************************************************************************************/
    /*** External Interactive Functions                                                         ***/
    /**********************************************************************************************/

    /// @inheritdoc IDefaultNFATPAUAssembler
    function deploy(
        PAUAssemblerConfigs       memory pauAssemblerConfigs,
        NFATFacilityFactoryConfig memory nfatFacilityFactoryConfig
    )
        external
        override
        returns (
            address          proxy,
            address          nfatFacility,
            address[] memory controllers,
            address[] memory accessControls,
            address[] memory rateLimits,
            address[] memory allocatorAgents
        )
    {
        // Step 1: Deploy and configure the full PAU stack via the PAUAssembler.

        ( proxy, controllers, accessControls, rateLimits, allocatorAgents ) = IPAUAssembler(pauAssembler)
            .deploy(
                pauAssemblerConfigs.controllerConfigs,
                pauAssemblerConfigs.rateLimitsConfigs,
                pauAssemblerConfigs.accessControlsConfigs,
                pauAssemblerConfigs.allocatorAgentConfigs,
                pauAssemblerConfigs.almProxyConfig
            );

        // Step 2: Deploy the NFAT facility wired to the shared ALMProxy.
        //         Split out into a helper to avoid stack-too-deep.

        nfatFacility = _deployNFATFacility(nfatFacilityFactoryConfig, proxy);

        emit Deployment(
            proxy,
            nfatFacility,
            controllers,
            accessControls,
            rateLimits,
            allocatorAgents,
            pauAssemblerConfigs,
            nfatFacilityFactoryConfig
        );
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _deployNFATFacility(NFATFacilityFactoryConfig memory nfatFacilityFactoryConfig, address almProxy)
        internal
        returns (address)
    {
        // The facility's recipient and sole bud are both the shared ALMProxy.

        address[] memory buds = new address[](1);

        buds[0] = almProxy;

        return INFATFacilityFactoryLike(nfatFacilityFactory)
            .deploy(
                nfatFacilityFactoryConfig.name,
                nfatFacilityFactoryConfig.symbol,
                nfatFacilityFactoryConfig.baseURI,
                nfatFacilityFactoryConfig.gem,
                almProxy,
                nfatFacilityFactoryConfig.identityNetwork,
                nfatFacilityFactoryConfig.wards,
                buds,
                nfatFacilityFactoryConfig.cops
            );
    }

}
