// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { AccessControls }    from "../../lib/diamond-pau/src/AccessControls.sol";
import { ALMProxy }          from "../../lib/diamond-pau/src/ALMProxy.sol";
import { ALMProxyFreezable } from "../../lib/diamond-pau/src/ALMProxyFreezable.sol";
import { RateLimits }        from "../../lib/diamond-pau/src/RateLimits.sol";

import {
    IPAUFactoryLike,
    IControllerLike
} from "../../src/PAUAdministeredAgentFactory.sol";

interface IHasRole {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

/// @notice Minimal ERC20 used to exercise a real TransferAssetFacet transfer end-to-end.
contract MockERC20 {

    string public constant name   = "Mock";
    string public constant symbol = "MOCK";
    uint8  public constant decimals = 18;

    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "MockERC20/insufficient-balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to]         += amount;
        return true;
    }

}

/**
 * @notice Stand-in for the diamond-pau Controller. It records the ids forwarded by the
 *         factory and faithfully reproduces the two checks the real
 *         `Controller.updateIntegrations` enforces that are observable from the factory:
 *           1. caller must hold DEFAULT_ADMIN_ROLE on the linked AccessControls, and
 *           2. the id array must be non-empty.
 *         This lets the unit tests exercise the factory's ordering (it must still be admin
 *         when it calls updateIntegrations) and the empty-integrations gap without standing
 *         up a full Beacon + facet deployment.
 */
contract MockController is IControllerLike {

    error NotAdmin(address caller);
    error EmptyArray();

    address public immutable accessControls;
    address public immutable proxy;
    address public immutable rateLimits;

    uint256 public updateIntegrationsCallCount;
    bytes32[] internal _lastIds;

    constructor(address accessControls_, address proxy_, address rateLimits_) {
        accessControls = accessControls_;
        proxy          = proxy_;
        rateLimits     = rateLimits_;
    }

    function updateIntegrations(bytes32[] calldata ids) external override {
        require(IHasRole(accessControls).hasRole(bytes32(0), msg.sender), NotAdmin(msg.sender));
        require(ids.length > 0, EmptyArray());

        _lastIds = ids;
        ++updateIntegrationsCallCount;
    }

    function lastIds() external view returns (bytes32[] memory) {
        return _lastIds;
    }

}

/**
 * @notice Stand-in for the diamond-pau PAUFactory that conforms to the factory's
 *         `IPAUFactoryLike` adapter interface. It deploys the *real* AccessControls,
 *         ALMProxy and RateLimits contracts (so role wiring is exercised against genuine
 *         AccessControl logic) and a {MockController} for the integration step.
 */
contract MockPAUFactory is IPAUFactoryLike {

    address public lastAccessControls;
    address public lastProxy;
    address public lastRateLimits;
    address public lastController;
    bool    public lastProxyFreezable;

    function deployAccessControls(address admin) external override returns (address accessControls) {
        accessControls     = address(new AccessControls(admin));
        lastAccessControls = accessControls;
    }

    function deployALMProxy(address admin) external override returns (address almProxy) {
        almProxy           = address(new ALMProxy(admin));
        lastProxy          = almProxy;
        lastProxyFreezable = false;
    }

    function deployALMProxyFreezable(address admin)
        external
        override
        returns (address almProxyFreezable)
    {
        almProxyFreezable  = address(new ALMProxyFreezable(admin));
        lastProxy          = almProxyFreezable;
        lastProxyFreezable = true;
    }

    function deployRateLimits(address admin) external override returns (address rateLimits) {
        rateLimits     = address(new RateLimits(admin));
        lastRateLimits = rateLimits;
    }

    function deployController(address accessControls, address proxy, address rateLimits)
        external
        override
        returns (address controller)
    {
        controller     = address(new MockController(accessControls, proxy, rateLimits));
        lastController = controller;
    }

}
