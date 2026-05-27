// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

interface IPAUFactoryLike {

    function deployAccessControls(address admin) external returns(address accessControls);

    function deployController(address accessControls, address proxy, address rateLimits)
            external
            returns (address controller);

    function deployProxy(address admin) external returns (address proxy);

    function deployProxyFreezable(address admin) external returns (address proxy);

    function deployRateLimits(address admin) external returns (address rateLimits);

}

interface IRateLimitsLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function CONTROLLER() external view returns (bytes32);

}

interface IALMProxyLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function CONTROLLER() external view returns (bytes32);

}

interface IAccessControlsLike {

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function setRoleAdmin(bytes32 role, address admin) external;
}

interface IControllerLike {

    function updateIntegrations(bytes32[] calldata ids) external;
}

contract FullSimplePAUFactory {

    event Deployed(
        address indexed admin,
        address accessControls,
        address controller,
        address proxy,
        address rateLimits,
        address administeredActor
    );

    IPAUFactoryLike public immutable pauFactory;

    bytes32 internal constant _DEFAULT_ADMIN_ROLE = 0x00;

    string public constant VERSION = "1.0.0";

    constructor(IPAUFactoryLike _pauFactory) {
        pauFactory = _pauFactory;
    }

    function deploy(
        address admin,
        bytes32[] calldata ids,
        address[] calldata actors,
        address[] calldata grantors,
        address[] calldata revokers
    )
        external
        returns(
            IAccessControlsLike accessControls,
            IControllerLike controller,
            IALMProxyLike proxy,
            IRateLimitsLike rateLimits
        ) {

        // Step 1: Deploy AccessControls, Proxy, RateLimits, and Controller
        accessControls = IAccessControlsLike(pauFactory.deployAccessControls(address(this)));
        proxy          = IALMProxyLike(pauFactory.deployProxy(address(this)));
        rateLimits     = IRateLimitsLike(pauFactory.deployRateLimits(address(this)));
        controller     = IControllerLike(pauFactory.deployController(address(accessControls), address(proxy), address(rateLimits)));

        // Step 2: Grant roles to Proxy, RateLimits, and Controller
        proxy.grantRole(proxy.CONTROLLER(),      address(controller));
        rateLimits.grantRole(proxy.CONTROLLER(), address(controller));

        proxy.grantRole(_DEFAULT_ADMIN_ROLE,          admin);
        accessControls.grantRole(_DEFAULT_ADMIN_ROLE, admin);

        //Step 3: Update Integrations on Controller
        IControllerLike(controller).updateIntegrations(ids);

        // Step 4: WIP - Need to Integrate AdministeredActor with [actors, grantors, revokers]

        //Step 5: Revoke Roles for Factory
        proxy.revokeRole(_DEFAULT_ADMIN_ROLE,      address(this));
        rateLimits.revokeRole(_DEFAULT_ADMIN_ROLE, address(this));

        emit Deployed(
            admin,
            address(accessControls),
            address(controller),
            address(proxy),
            address(rateLimits),
            address(0) // administeredActor — populated when Step 4 is implemented
        );

    }

}
