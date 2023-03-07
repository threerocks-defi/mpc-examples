// SPDX-License-Identifier: GPL-3.0-or-later
// TODO license
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// Core Infra
import "./NullController.sol";
import "../interfaces/IManagedPoolFactory.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/Create2.sol";

/**
 * @title NullControllerFactory
 * @notice Factory for a Managed Pool and NullController.
 * @dev Determines controller deployment address, deploys pool (w/ controller address as argument), then controller.
 */
contract NullControllerFactory {
    mapping(address => bool) public isControllerFromFactory;

    address public immutable managedPoolFactory;
    IVault public immutable balancerVault;
    bool public isDisabled;

    uint256 private _nextControllerSalt;
    address private _lastCreatedPool;

    event ControllerCreated(address indexed controller, IVault vault, bytes32 poolId);

    constructor(IVault vault, address factory) {
        balancerVault = vault;
        managedPoolFactory = factory;
    }

    /**
     * @dev Return the address of the most recently created pool.
     */
    function getLastCreatedPool() external view returns (address) {
        return _lastCreatedPool;
    }

    function create(IManagedPoolFactory.NewPoolParams memory params) external {
        if (!isDisabled) {
            bytes32 controllerSalt = bytes32(_nextControllerSalt);
            _nextControllerSalt += 1;

            bytes memory controllerCreationCode = abi.encodePacked(
                type(NullController).creationCode,
                abi.encode(balancerVault)
            );
            address expectedControllerAddress = Create2.computeAddress(
                controllerSalt,
                keccak256(controllerCreationCode)
            );

            // build arguments to deploy pool from factory
            address[] memory assetManagers = new address[](params.tokens.length);
            for (uint256 i = 0; i < assetManagers.length; i++) {
                assetManagers[i] = expectedControllerAddress;
            }

            // TODO: instead of accepting the entirety of IManagedPoolFactory.NewPoolParams and
            //       overwriting assetManagers and mustAllowlistLPs should we instead:
            //          * extract all arguments and pass them individually?
            //          * make a separate struct of the non-overwritten args, and use that to populate?
            params.assetManagers = assetManagers;
            params.mustAllowlistLPs = false;

            IManagedPool pool = IManagedPool(
                IManagedPoolFactory(managedPoolFactory).create(params, expectedControllerAddress)
            );
            _lastCreatedPool = address(pool);

            address actualControllerAddress = Create2.deploy(0, controllerSalt, controllerCreationCode);
            require(expectedControllerAddress == actualControllerAddress, "Deploy failed");

            // log controller locally
            isControllerFromFactory[actualControllerAddress] = true;

            // log controller publicly
            emit ControllerCreated(actualControllerAddress, balancerVault, pool.getPoolId());
        }
    }

    // TODO: access control
    function disable() external {
        isDisabled = true;
    }
}
