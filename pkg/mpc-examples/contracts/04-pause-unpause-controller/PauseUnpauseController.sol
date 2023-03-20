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

import "@openzeppelin/contracts/access/Ownable.sol";

contract PauseUnpauseController is Ownable {
    uint256 private constant _END_SWAP_FEE_PERCENTAGE = 3e15;
    uint256 private constant _START_SWAP_FEE_PERCENTAGE = 95e16;
    uint256 private constant _SWAP_FEE_REDUCATION_DURATION = 3 days;

    IVault private _vault;
    bytes32 private _poolId;

    constructor(IVault vault, address controllerOwner) {
        //Get poolId from the factory
        bytes32 poolId = IManagedPool(ILastCreatedPoolFactory(msg.sender).getLastCreatedPool()).getPoolId();

        // Verify that this is a real Vault and the pool is registered - this call will revert if not.
        vault.getPool(poolId);

        // store Vault, PoolId and pool
        _poolId = poolId;
        _vault = vault;

        // transfer ownership from factory to manager
        transferOwnership(controllerOwner);
    }

    /// === public Getters ===

    function getPoolId() public view returns (bytes32) {
        return _poolId;
    }

    function getVault() public view returns (IVault) {
        return _vault;
    }

    function getSwapEnabled() public view returns (bool) {
        return _getPool().getSwapEnabled();
    }

    function isPoolPaused() public view returns (bool) {
        return !_getPool().getSwapEnabled();
    }

    /// === Setters ===

    /**
     * @notice Disables swapping
     */
    function pausePool() external onlyOwner returns (bool) {
        require(getSwapEnabled(), "swapping with pool is already paused");
        _getPool().setSwapEnabled(false);
        require(!getSwapEnabled(), "pausing swapping with the pool failed");
        // pool is confirmed paused
        return true;
    }

    /**
     * @notice unpauses the pool in a safe or unsafe manner
     * @dev a safe unpause is desirable as the market likely had price movements
     * which have not been reflected in a paused pool. In order to not leak too much
     * arbitrage losses, the controller adjusts swap fees of the managed pool to
     * _START_SWAP_FEE_PERCENTAGE instantly let's the market bring the pool back into balance
     * via minimal viable arbitrage
     * @param shouldSafeUnpause decision to safely unpause the pool
     */

    /* solhint-disable not-rely-on-time */
    function unpausePool(bool shouldSafeUnpause) external onlyOwner returns (bool) {
        if (shouldSafeUnpause) {
            _getPool().updateSwapFeeGradually(
                block.timestamp,
                block.timestamp + _SWAP_FEE_REDUCATION_DURATION,
                _START_SWAP_FEE_PERCENTAGE,
                _END_SWAP_FEE_PERCENTAGE
            );
            // enabling swaps again after having updated the swap fee gradually is fine
            // even if the the start time is at a future time.
            _getPool().setSwapEnabled(true);
            return true;
        } else {
            _getPool().setSwapEnabled(true);
            return true;
        }
    }

    /* solhint-enable not-rely-on-time */

    /// === Private and Internal ===

    function _getPoolFromId(bytes32 poolId) internal pure returns (IManagedPool) {
        // 12 byte logical shift left to remove the nonce and specialization setting. We don't need to mask,
        // since the logical shift already sets the upper bits to zero.
        return IManagedPool(address(uint256(poolId) >> (12 * 8)));
    }

    function _getPool() internal view returns (IManagedPool) {
        return _getPoolFromId(_poolId);
    }
}
