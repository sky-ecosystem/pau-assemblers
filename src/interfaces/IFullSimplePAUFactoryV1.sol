// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

/**
 * @title  IFullSimplePAUFactoryV1
 * @notice External interface for the FullSimplePAUFactory, a one-shot helper that
 *         deploys and wires together a full PAU stack (AccessControls, ALMProxy,
 *         RateLimits, Controller, and AdministeredActor) atop an underlying
 *         IPAUFactoryLike, and transfers admin rights to the caller-supplied admin.
 */
interface IFullSimplePAUFactoryV1 {

    /**
     * @notice Emitted once a full PAU stack has been deployed and configured.
     * @param  admin             The address granted DEFAULT_ADMIN_ROLE on the deployed contracts.
     * @param  accessControls    The deployed AccessControls contract.
     * @param  controller        The deployed Controller contract.
     * @param  proxy             The deployed ALMProxy contract.
     * @param  rateLimits        The deployed RateLimits contract.
     * @param  administeredActor The deployed AdministeredActor contract.
     */
    event Deployed(
        address indexed admin,
        address accessControls,
        address controller,
        address proxy,
        address rateLimits,
        address administeredActor
    );

    /**
     * @notice Semantic version of this factory implementation.
     * @return The version string.
     */
    function VERSION() external view returns (string memory);

    /**
     * @notice The underlying PAU factory used to deploy each individual component.
     * @return The address of the IPAUFactoryLike-compatible factory.
     */
    function pauFactory() external view returns (address);

    /**
     * @notice Deploys a full PAU stack in a single transaction, wires up roles,
     *         registers integrations on the Controller, configures the
     *         AdministeredActor with the supplied actors/grantors/revokers, and
     *         transfers admin rights from this factory to `admin`.
     * @dev    Emits {Deployed} on completion. After this call, this factory holds
     *         no privileged roles on any of the returned contracts.
     * @param  admin             Address that will receive DEFAULT_ADMIN_ROLE on the deployed contracts.
     * @param  ids               Integration ids to register on the Controller via `updateIntegrations`.
     * @param  actors            Addresses to be configured as actors on the AdministeredActor.
     * @param  grantors          Addresses authorised to grant actor roles on the AdministeredActor.
     * @param  revokers          Addresses authorised to revoke actor roles on the AdministeredActor.
     * @return accessControls    The deployed AccessControls contract.
     * @return controller        The deployed Controller contract.
     * @return proxy             The deployed ALMProxy contract.
     * @return rateLimits        The deployed RateLimits contract.
     * @return administeredActor The deployed AdministeredActor contract.
     */
    function deploy(
        address admin,
        bytes32[] calldata ids,
        address[] calldata actors,
        address[] calldata grantors,
        address[] calldata revokers
    )
        external
        returns (
            address accessControls,
            address controller,
            address proxy,
            address rateLimits,
            address administeredActor
        );

}
