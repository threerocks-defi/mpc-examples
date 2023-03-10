// SPDX-License-Identifier: GPL-3.0-or-later
// TODO license
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/Create2.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "./WeightChanger.sol";
import "../interfaces/IManagedPoolFactory.sol";
/**
 * @title WeightChangerFactory
 * @notice Factory for a Managed Pool and Weight Changer Controller.
 * @dev Determines controller deployment address, deploys pool (w/ controller address as argument), then controller.
 */
contract WeightChangerFactory is Ownable {
    mapping(address => bool) public isControllerFromFactory;

    address public managedPoolFactory;
    IVault public balancerVault;
    bool public isDisabled;

    uint256 private _nextControllerSalt;
    address private _lastCreatedPool;

    // This struct is a subset of IManagedPoolFactory.NewPoolParams which omits arguments
    // that this factory will override and are therefore unnecessary to provide. It will
    // ultimately be used to populate IManagedPoolFactory.NewPoolParams.
    struct MinimalPoolParams {
        string name;
        string symbol;
        IERC20[] tokens;
        uint256[] normalizedWeights;
        uint256 swapFeePercentage;
        bool swapEnabledOnStart;
        uint256 managementAumFeePercentage;
        uint256 aumFeeId;
    }

    event ControllerCreated(address indexed controller, IVault vault, bytes32 poolId);
    event Disabled();

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

    function create(MinimalPoolParams memory minimalParams) external {
        require(!isDisabled, "Controller factory disabled");
        require(!IManagedPoolFactory(managedPoolFactory).isDisabled(), "Pool factory disabled");

        bytes32 controllerSalt = bytes32(_nextControllerSalt);
        _nextControllerSalt += 1;

        bytes memory controllerCreationCode = abi.encodePacked(
            type(WeightChanger).creationCode,
            abi.encode(balancerVault)
        );
        address expectedControllerAddress = Create2.computeAddress(controllerSalt, keccak256(controllerCreationCode));

        // Build arguments to deploy pool from factory.
        address[] memory assetManagers = new address[](minimalParams.tokens.length);
        for (uint256 i = 0; i < assetManagers.length; i++) {
            assetManagers[i] = expectedControllerAddress;
        }

        // Populate IManagedPoolFactory.NewPoolParams with arguments from MinimalPoolParams and
        // other arguments that this factory provides itself.
        IManagedPoolFactory.NewPoolParams memory fullParams;
        fullParams.name = minimalParams.name;
        fullParams.symbol = minimalParams.symbol;
        fullParams.tokens = minimalParams.tokens;
        fullParams.normalizedWeights = minimalParams.normalizedWeights;
        // Asset Managers set to the controller address, not known by deployer until creation.
        fullParams.assetManagers = assetManagers;
        fullParams.swapFeePercentage = minimalParams.swapFeePercentage;
        fullParams.swapEnabledOnStart = minimalParams.swapEnabledOnStart;
        // Factory enforces public LPs for MPs with NullController.
        fullParams.mustAllowlistLPs = false;
        fullParams.managementAumFeePercentage = minimalParams.managementAumFeePercentage;
        fullParams.aumFeeId = minimalParams.aumFeeId;

        IManagedPool pool = IManagedPool(
            IManagedPoolFactory(managedPoolFactory).create(fullParams, expectedControllerAddress)
        );
        _lastCreatedPool = address(pool);

        address actualControllerAddress = Create2.deploy(0, controllerSalt, controllerCreationCode);
        require(expectedControllerAddress == actualControllerAddress, "Deploy failed");

        // Log controller locally.
        isControllerFromFactory[actualControllerAddress] = true;

        // Log controller publicly.
        emit ControllerCreated(actualControllerAddress, balancerVault, pool.getPoolId());
    }

    /**
     * @dev Allow the owner to disable the factory, preventing future deployments.
     * @notice owner is initially the factory deployer, but this role can be transferred.
     * @dev The onlyOwner access control paradigm is an example. Any access control can
     * be implemented to allow for different needs.
     */
    function disable() external onlyOwner {
        isDisabled = true;
        emit Disabled();
    }
}
