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

import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/Create2.sol";

import "../interfaces/IManagedPoolFactory.sol";
import "./EBURebalancing.sol";

import { TestToken } from "@orbcollective/shared-dependencies/contracts/TestToken.sol";
import { TestWETH } from "@orbcollective/shared-dependencies/contracts/TestWETH.sol";

/**
 * @title EBURebalancingFactory
 * @notice Factory for a Managed Pool and EBURebalancing Controller.
 * @dev Determines controller deployment address, deploys pool (w/ controller address as argument), then controller.
 */
contract EBURebalancingFactory {
    mapping(address => bool) public isControllerFromFactory;

    address public immutable managedPoolFactory;
    IVault public immutable balancerVault;
    bool public isDisabled;

    uint256 private _nextControllerSalt;
    address private _lastCreatedPool;

    IManagedPoolFactory.NewPoolParams private _managedPoolParams =
        IManagedPoolFactory.NewPoolParams({
            name: "TestManagedPool",
            symbol: "TMP",
            tokens: new IERC20[](3),
            normalizedWeights: new uint256[](3),
            assetManagers: new address[](3),
            swapFeePercentage: 3e15,
            swapEnabledOnStart: true,
            mustAllowlistLPs: false,
            managementAumFeePercentage: 1e15,
            aumFeeId: 0
        });

    event ControllerCreated(address indexed controller, bytes32 poolId);

    constructor(IVault vault, address factory) {
        balancerVault = vault;
        managedPoolFactory = factory;

        // Set managed pool params
        _managedPoolParams.tokens[0] = new TestWETH(msg.sender);
        _managedPoolParams.tokens[2] = IERC20(address(new TestToken(msg.sender, "USDC", "USDC", 6)));
        _managedPoolParams.tokens[1] = IERC20(address(new TestToken(msg.sender, "WBTC", "WBTC", 8)));
        _managedPoolParams.normalizedWeights[0] = 3334e14;
        _managedPoolParams.normalizedWeights[1] = 3333e14;
        _managedPoolParams.normalizedWeights[2] = 3333e14;
        _managedPoolParams.assetManagers[0] = address(0);
        _managedPoolParams.assetManagers[1] = address(0);
        _managedPoolParams.assetManagers[2] = address(0);
    }

    /**
     * @dev Return the address of the most recently created pool.
     */
    function getLastCreatedPool() external view returns (address) {
        return _lastCreatedPool;
    }

    function create() external {
        require(!isDisabled, "Factory is disabled");

        bytes32 controllerSalt = bytes32(_nextControllerSalt);
        _nextControllerSalt += 1;

        bytes memory controllerCreationCode = abi.encodePacked(
            type(EBURebalancing).creationCode,
            abi.encode(balancerVault)
        );
        address expectedControllerAddress = Create2.computeAddress(controllerSalt, keccak256(controllerCreationCode));

        // build arguments to deploy pool from factory
        address[] memory assetManagers = new address[](_managedPoolParams.tokens.length);
        for (uint256 i = 0; i < assetManagers.length; i++) {
            assetManagers[i] = expectedControllerAddress;
        }

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
        emit ControllerCreated(actualControllerAddress, pool.getPoolId());
    }

    // TODO: access control
    function disable() external {
        isDisabled = true;
    }
}
