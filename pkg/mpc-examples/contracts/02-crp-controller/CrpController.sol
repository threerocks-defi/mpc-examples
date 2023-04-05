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

import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/ILastCreatedPoolFactory.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/SafeERC20.sol";

// import "@balancer-labs/v2-interfaces/contracts/pool-utils/SafeERC20.sol";

/**
 * @title CrpController
 * @notice This is a "Configurable Rights Pool" (CRP) Managed Pool Controller. It implements a
 * checklist-style of manager permissions. At construction, a deployer defines the permissions
 * that the manager has. After construction, permissions can be renounced but not added.
 *
 * @dev The controller implements (mostly) pass-throughs to the pool to send transactions or
 * revert if the action is not allowed. The two exceptions to pure pass-throughs are for addToken
 * and removeToken due to the additional steps needed handle the token transfers
 * via vault.managePoolBalance(...).
 */
contract CrpController {
    using SafeERC20 for IERC20;

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
        LENGTH
        // Using LENGTH since `type(<Enum>).max;` not implemented until 0.8.8
        // https://blog.soliditylang.org/2021/09/27/solidity-0.8.8-release-announcement/
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

    // Pass-through functions to the pool
    function addAllowedAddress(address member) external onlyManager hasRight(CrpRight.ADD_ALLOWED_ADDRESS) {
        _getPool().addAllowedAddress(member);
    }

    function removeAllowedAddress(address member) external onlyManager hasRight(CrpRight.REMOVE_ALLOWED_ADDRESS) {
        _getPool().removeAllowedAddress(member);
    }

    /**
     * @notice This is a one of two functions that is not a pure pass-through. Controllers must deposit tokens to a
     * pool via asset manager when using pool.addToken(...), so there this function must handle that as well.
     * @notice This requires a token allowance from the manager.
     */
    function addToken(IERC20 tokenToAdd, uint256 amount, uint256 tokenToAddNormalizedWeight, uint256 mintAmount, address recipient) external onlyManager hasRight(CrpRight.ADD_TOKEN) {
        _getPool().addToken(tokenToAdd, address(this), tokenToAddNormalizedWeight, mintAmount, recipient);
        tokenToAdd.safeTransferFrom(msg.sender, address(this), amount);
        IVault.PoolBalanceOp[] memory ops = new IVault.PoolBalanceOp[](1);
        ops[0] = IVault.PoolBalanceOp(IVault.PoolBalanceOpKind.DEPOSIT, getPoolId(), tokenToAdd, amount);
        getVault().managePoolBalance(ops);
    }

    /**
     * @notice This is a one of two functions that is not a pure pass-through. Controllers must withdraw tokens from a
     * pool via asset manager when using pool.removeToken(...), so there this function must handle that as well.
     */
    function removeToken(IERC20 tokenToRemove, uint256 burnAmount, address sender) external onlyManager hasRight(CrpRight.REMOVE_TOKEN) {
        IVault vault = getVault();

        // Ensure there is no managed balance. Force manager to handle any managed assets before removing.
        (uint256 cash, uint256 managed, ,) = vault.getPoolTokenInfo(getPoolId(), tokenToRemove);
        require(managed == 0, "Non-zero managed balance");

        // Remove full cash balance of tokenToRemove
        IVault.PoolBalanceOp[] memory ops = new IVault.PoolBalanceOp[](2);
        // Withdraw full balance from the Vault (this increases managed balance).
        ops[0] = IVault.PoolBalanceOp(IVault.PoolBalanceOpKind.WITHDRAW, getPoolId(), tokenToRemove, cash);
        // Set managed balance to zero since all tokens are going to manager here.
        ops[1] = IVault.PoolBalanceOp(IVault.PoolBalanceOpKind.UPDATE, getPoolId(), tokenToRemove, 0);
        vault.managePoolBalance(ops);
        tokenToRemove.safeTransfer(msg.sender, cash);

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
