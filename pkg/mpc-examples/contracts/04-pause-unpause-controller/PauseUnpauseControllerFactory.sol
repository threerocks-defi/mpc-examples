// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../interfaces/IManagedPoolFactory.sol";

import "@balancer-labs/v2-interfaces/contracts/pool-utils/ILastCreatedPoolFactory.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/Create2.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "./PauseUnpauseController.sol";

/**
 * @title PauseUnpauseControllerFactory
 * @notice A factory contract able to create controller contract for Balancer's managed pools.
 */
contract PauseUnpauseControllerFactory is Ownable {
    mapping(address => bool) public isControllerFromFactory;

    IManagedPoolFactory public immutable managedPoolFactory;
    bool private _disabled;
    IVault public immutable balancerVault;

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

    event ControllerCreated(address indexed controller, bytes32 poolId);
    event Disabled();

    constructor(IVault vault, address factory) {
        managedPoolFactory = IManagedPoolFactory(factory);
        balancerVault = vault;
    }

    /// === Getters === ///

    function isDisabled() public view returns (bool) {
        return _disabled;
    }

    function getLastCreatedPool() external view returns (address) {
        return _lastCreatedPool;
    }

    /// === Setters === ///

    function create(MinimalPoolParams calldata minimalParams, address controllerOwner, uint256 endSwapFeePercentage) external {
        // checks
        _ensureEnabled();

        bytes32 controllerSalt = bytes32(_nextControllerSalt);
        _nextControllerSalt += 1;

        bytes memory controllerCreationCode = abi.encodePacked(
            type(PauseUnpauseController).creationCode,
            abi.encode(balancerVault, controllerOwner, endSwapFeePercentage) //constructor args
        );

        address expectedControllerAddress = Create2.computeAddress(controllerSalt, keccak256(controllerCreationCode));

        // The asset managers have the ability to call vault.managePoolBalance. Since this controller
        // is focused on a secure pause/unpausing, allowing to freely pass asset managers
        // during pool creation could undermine the narrative that a paused pool does not have
        // any "token movements". Passing address(0) as the asset manager for all tokens ensures
        // assets cannot be moved via vault.manageBalance. This factory however passes the `expectedControllerAddress`
        // asthe asset managers, to indicate how passing custom asset managers would work.
        address[] memory assetManagers = new address[](minimalParams.tokens.length);
        for (uint256 i = 0; i < assetManagers.length; i++) {
            assetManagers[i] = expectedControllerAddress;
        }

        IManagedPoolFactory.NewPoolParams memory fullParams;
        fullParams.name = minimalParams.name;
        fullParams.symbol = minimalParams.symbol;
        fullParams.tokens = minimalParams.tokens;
        fullParams.normalizedWeights = minimalParams.normalizedWeights;
        fullParams.assetManagers = assetManagers;
        fullParams.swapFeePercentage = minimalParams.swapFeePercentage;
        fullParams.swapEnabledOnStart = minimalParams.swapEnabledOnStart;
        fullParams.mustAllowlistLPs = false;
        fullParams.managementAumFeePercentage = minimalParams.managementAumFeePercentage;
        fullParams.aumFeeId = minimalParams.aumFeeId;

        _lastCreatedPool = managedPoolFactory.create(fullParams, expectedControllerAddress);

        address actualControllerAddress = Create2.deploy(0, controllerSalt, controllerCreationCode);
        require(expectedControllerAddress == actualControllerAddress, "Deploy failed");

        // Log controller locally.
        isControllerFromFactory[actualControllerAddress] = true;

        // Log controller globally.
        emit ControllerCreated(actualControllerAddress, IManagedPool(_lastCreatedPool).getPoolId());
    }

    /**
     * @dev Allow the owner to disable the factory, preventing future deployments.
     * @notice owner is initially the factory deployer, but this role can be transferred.
     * @dev The onlyOwner access control paradigm is an example. Any access control can
     * be implemented to allow for different needs.
     */
    function disable() external onlyOwner {
        _ensureEnabled();
        _disabled = true;
        emit Disabled();
    }

    /// === Internal === ///

    function _ensureEnabled() internal view {
        require(!isDisabled(), "Controller factory is disabled");
        require(!managedPoolFactory.isDisabled(), "managed Pool factory disabled");
    }
}
