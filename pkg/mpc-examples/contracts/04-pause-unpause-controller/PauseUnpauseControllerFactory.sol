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

import "@balancer-labs/v2-interfaces/contracts/pool-utils/ILastCreatedPoolFactory.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/Create2.sol";

import "../interfaces/IManagedPoolFactory.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "./PauseUnpauseController.sol";

/**
 * @title
 * @notice
 * @dev
 */
contract PauseUnpauseControllerFactory is Ownable {
    mapping(address => bool) public isControllerFromFactory;

    IManagedPoolFactory public immutable managedPoolFactory;
    bool public isDisabled;
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
        // uint256[] assetManagers;
        uint256 swapFeePercentage;
        bool swapEnabledOnStart;
        bool mustAllowlistLPs;
        uint256 managementAumFeePercentage;
        uint256 aumFeeId;
    }

    event ControllerCreated(address indexed controller, bytes32 poolId);
    event Disabled();

    constructor(address factory, IVault vault) {
        managedPoolFactory = IManagedPoolFactory(factory);
        balancerVault = vault;
    }

    /// === Getters === ///
    function getLastCreatedPool() external view returns (address) {
        return _lastCreatedPool;
    }

    /// === Setters === ///

    function create(MinimalPoolParams memory minimalParams, address controllerOwner) external {
        // checks
        require(!isDisabled, "Controller factory is disabled");
        require(!managedPoolFactory.isDisabled(), "managed Pool factory disabled");

        bytes32 controllerSalt = bytes32(_nextControllerSalt);
        _nextControllerSalt += 1;

        bytes memory controllerCreationCode = abi.encodePacked(
            type(PauseUnpauseController).creationCode,
            abi.encode(balancerVault, controllerOwner) //constructor args
        );

        address expectedControllerAddress = Create2.computeAddress(controllerSalt, keccak256(controllerCreationCode));

        // The asset managers have the ability to manage poolTokens. Since this controller
        // is focused on a secure pause/unpausing, allowing to freely pass asset managers
        // during pool creation could undermine the narrative that a paused pool does not have
        // any "token movements". Passing the controller as asset manager (which does not have
        // any logic for that purpose) confirms that narrative for this example
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
        fullParams.mustAllowlistLPs = minimalParams.mustAllowlistLPs;
        fullParams.managementAumFeePercentage = minimalParams.managementAumFeePercentage;
        fullParams.aumFeeId = minimalParams.aumFeeId;

        _lastCreatedPool = managedPoolFactory.create(fullParams, expectedControllerAddress);

        address actualControllerAddress = Create2.deploy(0, controllerSalt, controllerCreationCode);
        require(expectedControllerAddress == actualControllerAddress, "Deploy failed");

        // Log controller locally
        isControllerFromFactory[actualControllerAddress] = true;

        // Log controller globally
        emit ControllerCreated(actualControllerAddress, IManagedPool(_lastCreatedPool).getPoolId());
    }

    function disable() external onlyOwner {
        isDisabled = true;
        emit Disabled();
    }
}
