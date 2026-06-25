// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IDefaultNFATAssembler } from "./interfaces/IDefaultNFATAssembler.sol";
import { IPAUAssembler }         from "./interfaces/IPAUAssembler.sol";

interface INFATFactoryLike {

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

contract DefaultNFATAssembler is IDefaultNFATAssembler {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IDefaultNFATAssembler
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IDefaultNFATAssembler
    address public immutable nfatFactory;

    /// @inheritdoc IDefaultNFATAssembler
    address public immutable pauAssembler;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address nfatFactory_, address pauAssembler_) {
        require(nfatFactory_  != address(0), ZeroNFATFactory());
        require(pauAssembler_ != address(0), ZeroPAUAssembler());

        nfatFactory  = nfatFactory_;
        pauAssembler = pauAssembler_;
    }

    /**********************************************************************************************/
    /*** External Interactive Functions                                                         ***/
    /**********************************************************************************************/

    /// @inheritdoc IDefaultNFATAssembler
    function deploy(
        PAUAssemblerInput memory pauAssemblerInput,
        NFATFactoryInput  memory nfatFactoryInput
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

        (proxy, controllers, accessControls, rateLimits, allocatorAgents) = IPAUAssembler(pauAssembler)
            .deploy(
                pauAssemblerInput.controllerConfigs,
                pauAssemblerInput.rateLimitConfigs,
                pauAssemblerInput.accessControlConfigs,
                pauAssemblerInput.allocatorAgentConfigs,
                pauAssemblerInput.almProxyConfig
            );

        // Step 2: Deploy the NFAT facility wired to the shared ALMProxy.
        //         Split out into a helper to avoid stack-too-deep.

        nfatFacility = _deployNFATFacility(nfatFactoryInput, proxy);

        emit Deployment(
            proxy,
            nfatFacility,
            controllers,
            accessControls,
            rateLimits,
            allocatorAgents,
            pauAssemblerInput,
            nfatFactoryInput
        );
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _deployNFATFacility(NFATFactoryInput memory nfatFactoryInput, address almProxy)
        internal
        returns (address)
    {
        // The facility's recipient and sole bud are both the shared ALMProxy.

        address[] memory buds = new address[](1);

        buds[0] = almProxy;

        return INFATFactoryLike(nfatFactory)
            .deploy(
                nfatFactoryInput.name,
                nfatFactoryInput.symbol,
                nfatFactoryInput.baseURI,
                nfatFactoryInput.gem,
                almProxy,
                nfatFactoryInput.identityNetwork,
                nfatFactoryInput.wards,
                buds,
                nfatFactoryInput.cops
            );
    }

}
