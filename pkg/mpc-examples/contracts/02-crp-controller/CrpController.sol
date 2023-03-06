// SPDX-License-Identifier: GPL-3.0-or-later
// TODO license
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/ILastCreatedPoolFactory.sol";

/**
 * @title CrpController
 * @notice This is a "Configurable Rights Pool" (CRP) Managed Pool Controller. It implements a 
 * checklist-style of manager permissions. At construction, a deployer defines the permissions 
 * that the manager has. The controller has simple passthroughs to the pool to send transactions 
 * or revert if the action is not allowed.
 */
contract CrpController {
    IVault private immutable _vault;
    bytes32 private immutable _poolId;
    address private immutable _manager;
    Rights private _rights;

    // Define the CrpRights associated with each Right (must be parallel)
    enum CrpRight {
        ADD_ALLOWED_ADDRESS,
        ADD_TOKEN,
        REMOVE_ALLOWED_ADDRESS,
        REMOVE_TOKEN,
        SET_CIRCUIT_BREAKERS,
        SET_JOIN_EXIT_ENABLED,
        SET_MANAGEMENT_AUM_FEE_PERCENTAGE,
        SET_MUST_ALLOWLIST_LPS,
        SET_SWAP_ENABLED,
        UPDATE_SWAP_FEE_GRADUALLY,
        UPDATE_WEIGHTS_GRADUALLY
    }

    // Set of flags indicating which rights have been reserved
    // They can be set to false through `renouncePermission`, but
    // never enabled after deployment
    struct Rights {
        bool addAllowedAddress;
        bool addToken;
        bool removeAllowedAddress;
        bool removeToken;
        bool setCircuitBreakers;
        bool setJoinExitEnabled;
        bool setManagementAumFeePercentage;
        bool setMustAllowlistLPs;
        bool setSwapEnabled;
        bool updateSwapFeeGradually;
        bool updateWeightsGradually;
    }

    modifier onlyManager() {
        require(msg.sender == _manager, "Caller not manager");
        _;
    }

    modifier hasRight(bool right) {
        require(right, "Right not granted");
        _;
    }

    constructor(IVault vault, address manager, Rights memory rights) {
        // Get poolId from the factory
        bytes32 poolId = IManagedPool(ILastCreatedPoolFactory(msg.sender).getLastCreatedPool()).getPoolId();

        // Verify that this is a real Vault and the pool is registered - this call will revert if not.
        vault.getPool(poolId);

        // Store Vault and poolId
        _vault = vault;
        _poolId = poolId;
        _manager = manager;
        _rights = rights;
    }

    function addAllowedAddress(address member) external onlyManager hasRight(_rights.addAllowedAddress) {
        _getPool().addAllowedAddress(member);
    }

    function removeAllowedAddress(address member) external onlyManager hasRight(_rights.removeAllowedAddress) {
        _getPool().removeAllowedAddress(member);
    }

    function removeToken(IERC20 tokenToRemove, uint256 burnAmount, address sender) external onlyManager hasRight(_rights.removeToken) {
        _getPool().removeToken(tokenToRemove, burnAmount, sender);
    }

    function setCircuitBreakers(IERC20[] calldata tokens, uint256[] calldata bptPrices, uint256[] calldata lowerBoundPercentages, uint256[] calldata upperBoundPercentages) external onlyManager hasRight(_rights.setCircuitBreakers) {
        _getPool().setCircuitBreakers(tokens, bptPrices, lowerBoundPercentages, upperBoundPercentages);
    }

    // TODO: uncomment after new MP release adds this feature
    // function setJoinExitEnabled(bool enabled) external onlyManager hasRight(_rights.setJoinExitEnabled) {
    //     _getPool().setJoinExitEnabled(enabled);
    // }

    function setManagementAumFeePercentage(uint256 managementAumFeePercentage) external onlyManager hasRight(_rights.setManagementAumFeePercentage) {
        _getPool().setManagementAumFeePercentage(managementAumFeePercentage);
    }

    function setMustAllowlistLPs(bool mustAllowlistLPs) external onlyManager hasRight(_rights.setMustAllowlistLPs) {
        _getPool().setMustAllowlistLPs(mustAllowlistLPs);
    }

    function setSwapEnabled(bool swapEnabled) external onlyManager hasRight(_rights.setSwapEnabled) {
        _getPool().setSwapEnabled(swapEnabled);
    }

    function updateSwapFeeGradually(uint256 startTime, uint256 endTime, uint256 startSwapFeePercentage, uint256 endSwapFeePercentage) external onlyManager hasRight(_rights.updateSwapFeeGradually) {
        _getPool().updateSwapFeeGradually(startTime, endTime, startSwapFeePercentage, endSwapFeePercentage);
    }

    function updateWeightsGradually(uint256 startTime, uint256 endTime, IERC20[] calldata tokens, uint256[] calldata endWeights) external onlyManager hasRight(_rights.updateWeightsGradually) {
        _getPool().updateWeightsGradually(startTime, endTime, tokens, endWeights);
    }

    function renounceRight(CrpRight right) external onlyManager {
        if (CrpRight.ADD_ALLOWED_ADDRESS == right) {
            _rights.addAllowedAddress = false;
        } else if (CrpRight.ADD_TOKEN == right) {
            _rights.addToken = false;
        } else if (CrpRight.REMOVE_ALLOWED_ADDRESS == right) {
            _rights.removeAllowedAddress = false;
        } else if (CrpRight.REMOVE_TOKEN == right) {
            _rights.removeToken = false;
        } else if (CrpRight.SET_CIRCUIT_BREAKERS == right) {
            _rights.setCircuitBreakers = false;
        } else if (CrpRight.SET_JOIN_EXIT_ENABLED == right) {
            _rights.setJoinExitEnabled = false;
        } else if (CrpRight.SET_MANAGEMENT_AUM_FEE_PERCENTAGE == right) {
            _rights.setManagementAumFeePercentage = false;
        } else if (CrpRight.SET_MUST_ALLOWLIST_LPS == right) {
            _rights.setMustAllowlistLPs = false;
        } else if (CrpRight.SET_SWAP_ENABLED == right) {
            _rights.setSwapEnabled = false;
        } else if (CrpRight.UPDATE_SWAP_FEE_GRADUALLY == right) {
            _rights.updateSwapFeeGradually = false;
        } else if (CrpRight.UPDATE_WEIGHTS_GRADUALLY == right) {
            _rights.updateWeightsGradually = false;
        } else {
            revert("Invalid right");
        }
    }

    function getPoolId() public view returns (bytes32) {
        return _poolId;
    }

    function getVault() public view returns (IVault) {
        return _vault;
    }

    function _getPool() internal view returns (IManagedPool) {
        // 12 byte logical shift left to remove the nonce and specialization setting. We don't need to mask,
        // since the logical shift already sets the upper bits to zero.
        return IManagedPool(uint256(_poolId) >> (12 * 8));
    }

    function getRights() external view returns(Rights memory) {
        return _rights;
    }
}
