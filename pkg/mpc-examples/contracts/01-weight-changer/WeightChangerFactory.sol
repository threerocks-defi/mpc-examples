// SPDX-License-Identifier: GPL-3.0-or-later
// TODO license
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// Core Infra
import "./WeightChanger.sol";
import "../interfaces/IManagedPoolFactory.sol";

import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/Create2.sol";

import { TestToken } from "@orbcollective/shared-dependencies/contracts/TestToken.sol";
import { TestWETH } from "@orbcollective/shared-dependencies/contracts/TestWETH.sol";

/**
 * @title WeightChangerFactory
 * @notice Factory for a Managed Pool and Weight Changer Controller.
 * @dev Determines controller deployment address, deploys pool (w/ controller address as argument), then controller.
 */
contract WeightChangerFactory {
    mapping(address => bool) public isControllerFromFactory;

    address public managedPoolFactory;
    IVault public balancerVault;
    bool public isDisabled;

    uint256 private _nextControllerSalt;
    address private _lastCreatedPool;

    IManagedPoolFactory.NewPoolParams private _managedPoolParams =
        IManagedPoolFactory.NewPoolParams({
            name: "TestManagedPool",
            symbol: "TMP",
            tokens: new IERC20[](2),
            normalizedWeights: new uint256[](2),
            assetManagers: new address[](2),
            swapFeePercentage: 3e15,
            swapEnabledOnStart: true,
            mustAllowlistLPs: false,
            managementAumFeePercentage: 1e15,
            aumFeeId: 0
        });

    event ControllerCreated(address indexed controller, IVault vault, bytes32 poolId);

    constructor(IVault vault, address factory) {
        balancerVault = vault;
        managedPoolFactory = factory;

        // Set mananaged pool params
        _managedPoolParams.tokens[0] = new TestWETH(msg.sender);
        _managedPoolParams.tokens[1] = IERC20(address(new TestToken(msg.sender, "USDC", "USDC", 6)));
        _managedPoolParams.normalizedWeights[0] = 30e16;
        _managedPoolParams.normalizedWeights[1] = 70e16;
        _managedPoolParams.assetManagers[0] = address(0);
        _managedPoolParams.assetManagers[1] = address(1);
    }

    /**
     * @dev Return the address of the most recently created pool.
     */
    function getLastCreatedPool() external view returns (address) {
        return _lastCreatedPool;
    }

    function create() external {
        if (!isDisabled) {
            bytes32 controllerSalt = bytes32(_nextControllerSalt);
            _nextControllerSalt += 1;

            bytes memory controllerCreationCode = abi.encodePacked(
                type(WeightChanger).creationCode,
                abi.encode(balancerVault)
            );
            address expectedControllerAddress = Create2.computeAddress(
                controllerSalt,
                keccak256(controllerCreationCode)
            );

            // build arguments to deploy pool from factory
            address[] memory assetManagers = new address[](_managedPoolParams.tokens.length);
            for (uint256 i = 0; i < assetManagers.length; i++) {
                assetManagers[i] = expectedControllerAddress;
            }

            // TODO: instead of accepting the entirety of IManagedPoolFactory.NewPoolParams and
            //       overwriting assetManagers and mustAllowlistLPs should we instead:
            //          * extract all arguments and pass them individually?
            //          * make a separate struct of the non-overwritten args, and use that to populate?
            _managedPoolParams.assetManagers = assetManagers;
            _managedPoolParams.mustAllowlistLPs = false;

            IManagedPool pool = IManagedPool(
                IManagedPoolFactory(managedPoolFactory).create(_managedPoolParams, expectedControllerAddress)
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
