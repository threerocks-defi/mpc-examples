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
    mapping(CrpRight => bool) private _rights;

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
        UPDATE_WEIGHTS_GRADUALLY,
        LENGTH // Using LENGTH since `type(<Enum>).max;` not implemented until 0.8.8
    }

    modifier onlyManager() {
        require(msg.sender == _manager, "Caller not manager");
        _;
    }

    modifier hasRight(CrpRight right) {
        require(_hasRight(right), "Right not granted");
        _;
    }

    event AddRight(CrpRight);
    event RemoveRight(CrpRight);

    constructor(IVault vault, address manager, CrpRight[] memory rights) {
        // Get poolId from the factory
        bytes32 poolId = IManagedPool(ILastCreatedPoolFactory(msg.sender).getLastCreatedPool()).getPoolId();

        // Verify that this is a real Vault and the pool is registered - this call will revert if not.
        vault.getPool(poolId);

        // Store Vault and poolId
        _vault = vault;
        _poolId = poolId;
        _manager = manager;

        for (uint256 i = 0; i < rights.length; i++) {
            _validateRight(rights[i]);
            _rights[rights[i]] = true;
            emit AddRight(rights[i]);
        }
    }

    // Passthrough functions to the pool
    function addAllowedAddress(address member) external onlyManager hasRight(CrpRight.ADD_ALLOWED_ADDRESS) {
        _getPool().addAllowedAddress(member);
    }

    function removeAllowedAddress(address member) external onlyManager hasRight(CrpRight.REMOVE_ALLOWED_ADDRESS) {
        _getPool().removeAllowedAddress(member);
    }

    function addToken(IERC20 tokenToRemove, uint256 burnAmount, address sender) external onlyManager hasRight(CrpRight.ADD_TOKEN) {
        _getPool().removeToken(tokenToRemove, burnAmount, sender);
    }

    function removeToken(IERC20 tokenToRemove, uint256 burnAmount, address sender) external onlyManager hasRight(CrpRight.REMOVE_TOKEN) {
        _getPool().removeToken(tokenToRemove, burnAmount, sender);
    }

    function setCircuitBreakers(IERC20[] calldata tokens, uint256[] calldata bptPrices, uint256[] calldata lowerBoundPercentages, uint256[] calldata upperBoundPercentages) external onlyManager hasRight(CrpRight.SET_CIRCUIT_BREAKERS) {
        _getPool().setCircuitBreakers(tokens, bptPrices, lowerBoundPercentages, upperBoundPercentages);
    }

    // TODO: uncomment after new MP release adds this feature
    // function setJoinExitEnabled(bool enabled) external onlyManager hasRight(CrpRight.setJoinExitEnabled) {
    //     _getPool().setJoinExitEnabled(enabled);
    // }

    function setManagementAumFeePercentage(uint256 managementAumFeePercentage) external onlyManager hasRight(CrpRight.SET_MANAGEMENT_AUM_FEE_PERCENTAGE) {
        _getPool().setManagementAumFeePercentage(managementAumFeePercentage);
    }

    function setMustAllowlistLPs(bool mustAllowlistLPs) external onlyManager hasRight(CrpRight.SET_MUST_ALLOWLIST_LPS) {
        _getPool().setMustAllowlistLPs(mustAllowlistLPs);
    }

    function setSwapEnabled(bool swapEnabled) external onlyManager hasRight(CrpRight.SET_SWAP_ENABLED) {
        _getPool().setSwapEnabled(swapEnabled);
    }

    function updateSwapFeeGradually(uint256 startTime, uint256 endTime, uint256 startSwapFeePercentage, uint256 endSwapFeePercentage) external onlyManager hasRight(CrpRight.UPDATE_SWAP_FEE_GRADUALLY) {
        _getPool().updateSwapFeeGradually(startTime, endTime, startSwapFeePercentage, endSwapFeePercentage);
    }

    function updateWeightsGradually(uint256 startTime, uint256 endTime, IERC20[] calldata tokens, uint256[] calldata endWeights) external onlyManager hasRight(CrpRight.UPDATE_WEIGHTS_GRADUALLY) {
        _getPool().updateWeightsGradually(startTime, endTime, tokens, endWeights);
    }

    // Rights functions
    function renounceRight(CrpRight right) external onlyManager {
        _rights[right] = false;
        emit RemoveRight(right);
    }

    function hasRights(CrpRight right) external view returns(bool) {
        return _hasRight(right);
    }

    function getAllRights() external view returns(bool[] memory) {

        uint8 numRights = uint8(CrpRight.LENGTH);
        // uint256 numRights = type(CrpRight).max;
        //      not implemented until 0.8.8
        //      https://blog.soliditylang.org/2021/09/27/solidity-0.8.8-release-announcement/

        bool[] memory rights = new bool[](numRights);
        for (uint8 i = 0; i < numRights; i++) {
            rights[i] = _hasRight(CrpRight(i));
        }
        return rights;
    }

    // Basic Getters
    function getPoolId() public view returns (bytes32) {
        return _poolId;
    }

    function getVault() public view returns (IVault) {
        return _vault;
    }

    // Internal Helpers
    function _getPool() internal view returns (IManagedPool) {
        // 12 byte logical shift left to remove the nonce and specialization setting. We don't need to mask,
        // since the logical shift already sets the upper bits to zero.
        return IManagedPool(uint256(_poolId) >> (12 * 8));
    }

    function _hasRight(CrpRight right) internal view returns(bool) {
        return _rights[right];
    }

    function _validateRight(CrpRight right) internal pure {
        require(right < CrpRight.LENGTH, "Invalid right");
    }

}
