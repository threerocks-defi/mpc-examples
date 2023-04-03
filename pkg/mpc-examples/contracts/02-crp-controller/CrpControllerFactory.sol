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

// Core Infra
import "./CrpController.sol";
import "../interfaces/IManagedPoolFactory.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/Create2.sol";

/**
 * @title CrpControllerFactory
 * @notice Factory for a Managed Pool and CrpController.
 * @dev Determines controller deployment address, deploys pool (w/ controller address as argument), then controller.
 */
contract CrpControllerFactory {
    mapping(address => bool) public isControllerFromFactory;

    address public managedPoolFactory;
    IVault public balancerVault;
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

    function create(IManagedPoolFactory.NewPoolParams memory params, address manager, CrpController.CrpRight[] calldata rights) external {
        if (!isDisabled) {
            bytes32 controllerSalt = bytes32(_nextControllerSalt);
            _nextControllerSalt += 1;

            bytes memory controllerCreationCode = abi.encodePacked(
                type(CrpController).creationCode,
                abi.encode(balancerVault, manager, rights)
            );
            address expectedControllerAddress = Create2.computeAddress(
                controllerSalt,
                keccak256(controllerCreationCode)
            );

            bool usingAddRemoveToken;
            for (uint256 i = 0; i < rights.length; i++) {
                if (rights[i] == CrpController.CrpRight.ADD_TOKEN || rights[i] == CrpController.CrpRight.REMOVE_TOKEN) {
                    usingAddRemoveToken = true;
                    break;
                }
            }

            // build arguments to deploy pool from factory
            // only set controller as Asset Manager if it has add/remove rights
            address[] memory assetManagers = new address[](params.tokens.length);
            if (usingAddRemoveToken) {
                for (uint256 i = 0; i < assetManagers.length; i++) {
                    assetManagers[i] = expectedControllerAddress;
                }    
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
