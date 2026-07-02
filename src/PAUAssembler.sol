// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IPAUAssembler } from "./interfaces/IPAUAssembler.sol";

interface IALMProxyLike {

    function CONTROLLER() external view returns (bytes32);

}

interface IAccessControlLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

}

interface IAdministeredAgentFactoryLike {

    function deploy(address admin) external returns (address);

}

interface IAdministeredAgentLike {

    function addActor(address actor) external;

    function addAdmin(address admin) external;

    function addGrantor(address grantor) external;

    function addRevoker(address revoker) external;

    function removeAdmin(address admin) external;

}

interface IControllerLike {

    function updateIntegrations(bytes32[] calldata ids) external;

}

interface IPAUFactoryLike {

    function deployAccessControls(address admin) external returns (address accessControls);

    function deployALMProxy(address admin) external returns (address almProxy);

    function deployController(address accessControls, address proxy, address rateLimits)
        external
        returns (address controller);

    function deployRateLimits(address admin) external returns (address rateLimits);

}

interface IRateLimitsLike {

    function CONTROLLER() external view returns (bytes32);

}

contract PAUAssembler is IPAUAssembler {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _ALLOCATOR_ROLE     = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant _DEFAULT_ADMIN_ROLE = 0x00;

    /// @inheritdoc IPAUAssembler
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IPAUAssembler
    address public immutable administeredAgentFactory;

    /// @inheritdoc IPAUAssembler
    address public immutable pauFactory;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address administeredAgentFactory_, address pauFactory_) {
        require(administeredAgentFactory_ != address(0), ZeroAdministeredAgentFactory());
        require(pauFactory_               != address(0), ZeroPAUFactory());

        administeredAgentFactory = administeredAgentFactory_;
        pauFactory               = pauFactory_;
    }

    /**********************************************************************************************/
    /*** External Interactive Functions                                                         ***/
    /**********************************************************************************************/

    /// @inheritdoc IPAUAssembler
    function deploy(
        ControllerConfig[]        memory controllerConfigs,
        RateLimitConfig[]         memory rateLimitConfigs,
        AccessControlsConfig[]    memory accessControlsConfigs,
        AdministeredAgentConfig[] memory allocatorAgentConfigs,
        ALMProxyConfig            memory almProxyConfig
    )
        external
        override
        returns (
            address          proxy,
            address[] memory controllers,
            address[] memory accessControls,
            address[] memory rateLimits,
            address[] memory allocatorAgents
        )
    {
        // Step 1: Allocate return arrays.

        controllers     = new address[](controllerConfigs.length);
        accessControls  = new address[](accessControlsConfigs.length);
        rateLimits      = new address[](rateLimitConfigs.length);
        allocatorAgents = new address[](allocatorAgentConfigs.length);

        // Step 2: Deploy the shared ALMProxy and grant its admins.

        proxy = IPAUFactoryLike(pauFactory).deployALMProxy(address(this));

        _grantDefaultAdmins(proxy, almProxyConfig.admins);

        // Step 3: Deploy and configure all AccessControls, indexing each by its id.

        for (uint256 i = 0; i < accessControlsConfigs.length; i++) {
            AccessControlsConfig memory config = accessControlsConfigs[i];

            address accessControls_ =
                IPAUFactoryLike(pauFactory).deployAccessControls(address(this));

            accessControls[i] = accessControls_;

            bytes32 key = _getAccessControlId(config.id);

            require(_tloadAddress(key) == address(0), DuplicateAccessControlsId(config.id));

            _tstoreAddress(key, accessControls_);

            _grantDefaultAdmins(accessControls_, config.admins);
        }

        // Step 4: Deploy and configure all RateLimits, indexing each by its id.

        for (uint256 i = 0; i < rateLimitConfigs.length; i++) {
            RateLimitConfig memory config = rateLimitConfigs[i];

            address rateLimit = IPAUFactoryLike(pauFactory).deployRateLimits(address(this));

            rateLimits[i] = rateLimit;

            bytes32 key = _getRateLimitId(config.id);

            require(_tloadAddress(key) == address(0), DuplicateRateLimitsId(config.id));

            _tstoreAddress(key, rateLimit);

            _grantDefaultAdmins(rateLimit, config.admins);
        }

        // Step 5: Deploy all Controllers, wiring each to its referenced AccessControls and
        //         RateLimits and granting it CONTROLLER on the proxy and that RateLimits.

        for (uint256 i = 0; i < controllerConfigs.length; i++) {
            ControllerConfig memory config = controllerConfigs[i];

            address rateLimit       = _tloadAddress(_getRateLimitId(config.rateLimitId));
            address accessControls_ = _tloadAddress(_getAccessControlId(config.accessControlsId));

            require(rateLimit       != address(0), InvalidRateLimitsId(config.rateLimitId));
            require(accessControls_ != address(0), InvalidAccessControlsId(config.accessControlsId));

            address controller =
                IPAUFactoryLike(pauFactory).deployController(accessControls_, proxy, rateLimit);

            controllers[i] = controller;

            if (config.integrationIds.length > 0) {
                IControllerLike(controller).updateIntegrations(config.integrationIds);
            }

            IAccessControlLike(proxy).grantRole(IALMProxyLike(proxy).CONTROLLER(),           controller);
            IAccessControlLike(rateLimit).grantRole(IRateLimitsLike(rateLimit).CONTROLLER(), controller);
        }

        // Step 6: Deploy and configure all allocator agents, granting each the allocator role on
        //         its referenced AccessControls.

        for (uint256 i = 0; i < allocatorAgentConfigs.length; i++) {
            AdministeredAgentConfig memory config = allocatorAgentConfigs[i];

            address agent =
                IAdministeredAgentFactoryLike(administeredAgentFactory).deploy(address(this));

            allocatorAgents[i] = agent;

            _configureAgent(agent, config);

            address accessControls_ = _tloadAddress(_getAccessControlId(config.accessControlsId));

            require(accessControls_ != address(0), InvalidAccessControlsId(config.accessControlsId));

            IAccessControlLike(accessControls_).grantRole(_ALLOCATOR_ROLE, agent);

            IAdministeredAgentLike(agent).removeAdmin(address(this));
        }

        // Step 7: Revoke all roles from the assembler.

        _revokeSelf(accessControls);
        _revokeSelf(rateLimits);

        IAccessControlLike(proxy).revokeRole(_DEFAULT_ADMIN_ROLE, address(this));

        // Step 8: Clear the transient storage used for id cross-referencing within this call, so a
        //         second `deploy` in the same transaction starts from a clean slate. Keys are
        //         recomputed from the configs rather than tracked in a memory array, which would
        //         otherwise push this function past the stack limit (no via-IR).

        for (uint256 i = 0; i < accessControlsConfigs.length; i++) {
            _tstoreAddress(_getAccessControlId(accessControlsConfigs[i].id), address(0));
        }

        for (uint256 i = 0; i < rateLimitConfigs.length; i++) {
            _tstoreAddress(_getRateLimitId(rateLimitConfigs[i].id), address(0));
        }

        emit Deployment(
            proxy,
            controllers,
            accessControls,
            rateLimits,
            allocatorAgents,
            controllerConfigs,
            rateLimitConfigs,
            accessControlsConfigs,
            allocatorAgentConfigs,
            almProxyConfig
        );
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _configureAgent(address agent, AdministeredAgentConfig memory config) internal {
        require(config.admins.length > 0, NoAgentAdmins());

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

    function _grantDefaultAdmins(address target, address[] memory admins) internal {
        require(admins.length > 0, NoDefaultAdmins());

        for (uint256 i = 0; i < admins.length; ++i) {
            require(admins[i] != address(0), ZeroDefaultAdmin());

            IAccessControlLike(target).grantRole(_DEFAULT_ADMIN_ROLE, admins[i]);
        }
    }

    function _revokeSelf(address[] memory targets) internal {
        for (uint256 i = 0; i < targets.length; ++i) {
            IAccessControlLike(targets[i]).revokeRole(_DEFAULT_ADMIN_ROLE, address(this));
        }
    }

    function _tloadAddress(bytes32 id) internal view returns (address a) {
        assembly {
            a := tload(id)
        }
    }

    function _tstoreAddress(bytes32 id, address a) internal {
        assembly {
            tstore(id, a)
        }
    }

    function _getRateLimitId(bytes32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(bytes32("RATE_LIMIT"), id));
    }

    function _getAccessControlId(bytes32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(bytes32("ACCESS_CONTROL"), id));
    }

}
