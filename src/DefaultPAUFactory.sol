// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IDefaultPAUFactory } from "./interfaces/IDefaultPAUFactory.sol";

interface IPAUFactoryLike {

    function deployAccessControls(address admin) external returns(address accessControls);

    function deployALMProxy(address admin) external returns (address almProxy);

    function deployController(address accessControls, address proxy, address rateLimits)
        external
        returns (address controller);

    function deployRateLimits(address admin) external returns (address rateLimits);

}

interface IAdministeredAgentFactoryLike {

    function deploy(address admin) external returns(address);

}

interface IAccessControlLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

}

interface IRateLimitsLike {

    function CONTROLLER() external view returns (bytes32);

}

interface IALMProxyLike {

    function CONTROLLER() external view returns (bytes32);

}

interface IControllerLike {

    function updateIntegrations(bytes32[] calldata ids) external;
}

interface IAdministeredAgentLike {

    function addActor(address actor) external;

    function addAdmin(address admin) external;

    function addGrantor(address grantor) external;

    function addRevoker(address revoker) external;

    function removeAdmin(address admin) external;

}

contract DefaultPAUFactory is IDefaultPAUFactory {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 internal constant _ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    /// @inheritdoc IDefaultPAUFactory
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IDefaultPAUFactory
    address public immutable pauFactory;

    /// @inheritdoc IDefaultPAUFactory
    address public immutable administeredAgentFactory;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address pauFactory_, address administeredAgentFactory_) {
        require(pauFactory_ != address(0),               ZeroPAUFactory());
        require(administeredAgentFactory_ != address(0), ZeroAdministeredAgentFactory());

        pauFactory               = pauFactory_;
        administeredAgentFactory = administeredAgentFactory_;
    }

    /**********************************************************************************************/
    /*** External Interactive Functions                                                         ***/
    /**********************************************************************************************/

    /// @inheritdoc IDefaultPAUFactory
    function deploy(
        bytes32[]                 memory integrationIds,
        AdminConfig               memory adminConfig,
        AdministeredAgentConfig[] memory allocatorAgentConfigs
    )
        external
        override
        returns (
            address          proxy,
            address          controller,
            address          accessControls,
            address          rateLimits,
            address[] memory allocatorAgents
        )
    {
        accessControls = IPAUFactoryLike(pauFactory).deployAccessControls(address(this));
        proxy          = IPAUFactoryLike(pauFactory).deployALMProxy(address(this));
        rateLimits     = IPAUFactoryLike(pauFactory).deployRateLimits(address(this));

        controller =
            IPAUFactoryLike(pauFactory).deployController(accessControls, proxy, rateLimits);

        allocatorAgents = new address[](allocatorAgentConfigs.length);

        for (uint256 i = 0; i < allocatorAgentConfigs.length; i++) {
            allocatorAgents[i] =
                IAdministeredAgentFactoryLike(administeredAgentFactory).deploy(address(this));

            _configureAgent(allocatorAgents[i], allocatorAgentConfigs[i]);

            IAdministeredAgentLike(allocatorAgents[i]).removeAdmin(address(this));
        }

        _grantRoles(accessControls, controller, proxy, rateLimits, adminConfig, allocatorAgents);

        if (integrationIds.length > 0) {
            IControllerLike(controller).updateIntegrations(integrationIds);
        }

        IAccessControlLike(accessControls).revokeRole(_DEFAULT_ADMIN_ROLE, address(this));
        IAccessControlLike(proxy).revokeRole(_DEFAULT_ADMIN_ROLE,          address(this));
        IAccessControlLike(rateLimits).revokeRole(_DEFAULT_ADMIN_ROLE,     address(this));

        emit Deployment(
            proxy,
            controller,
            accessControls,
            rateLimits,
            allocatorAgents,
            integrationIds,
            adminConfig,
            allocatorAgentConfigs
        );
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _configureAgent(address agent, AdministeredAgentConfig memory config) internal {
        require(config.admins.length > 0, NoAdmins());

        for (uint256 i = 0; i < config.admins.length; ++i) {
            IAdministeredAgentLike(agent).addAdmin(config.admins[i]);
        }

        for (uint256 i = 0; i < config.actors.length; ++i) {
            IAdministeredAgentLike(agent).addActor(config.actors[i]);
        }

        for (uint256 i = 0; i < config.grantors.length; ++i) {
            IAdministeredAgentLike(agent).addGrantor(config.grantors[i]);
        }

        for (uint256 i = 0; i < config.revokers.length; ++i) {
            IAdministeredAgentLike(agent).addRevoker(config.revokers[i]);
        }
    }

    function _grantRoles(
        address            accessControls,
        address            controller,
        address            proxy,
        address            rateLimits,
        AdminConfig memory adminConfig,
        address[]   memory allocators
    )
        internal
    {
        _grantDefaultAdmins(proxy, adminConfig.proxyAdmins);
        IAccessControlLike(proxy).grantRole(IALMProxyLike(proxy).CONTROLLER(), controller);

        _grantDefaultAdmins(rateLimits, adminConfig.rateLimitsAdmins);
        IAccessControlLike(rateLimits).grantRole(IRateLimitsLike(rateLimits).CONTROLLER(), controller);

        _grantDefaultAdmins(accessControls, adminConfig.accessControlAdmins);

        for (uint256 i = 0; i < allocators.length; ++i) {
            IAccessControlLike(accessControls).grantRole(_ALLOCATOR_ROLE, allocators[i]);
        }
    }

    function _grantDefaultAdmins(address target, address[] memory admins) internal {
        require(admins.length > 0, NoAdmins());

        for (uint256 i = 0; i < admins.length; ++i) {
            require(admins[i] != address(0), ZeroAdmin());
            IAccessControlLike(target).grantRole(_DEFAULT_ADMIN_ROLE, admins[i]);
        }
    }

}
