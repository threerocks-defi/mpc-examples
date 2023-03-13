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
import "@balancer-labs/v2-pool-utils/contracts/lib/ComposablePoolLib.sol";

contract EBURebalancer {
    IVault private immutable _vault;
    bytes32 private immutable _poolId;
    IManagedPool private immutable _pool;

    uint256 private constant _MINIMUM_DURATION_BETWEEN_REBALANCE = 30 days;
    uint256 private constant _REBALANCE_DURATION = 7 days;
    uint256 private _lastRebalanceCall;

    event PoolRebalancing(uint256 indexed startBlock, uint256 endBlock);

    constructor(IVault vault) {
        // Get poolId from the factory
        bytes32 poolId = IManagedPool(ILastCreatedPoolFactory(msg.sender).getLastCreatedPool()).getPoolId();

        // Verify that this is a real Vault and the pool is registered - this call will revert if not.
        vault.getPool(poolId);

        // Store Vault and poolId
        _vault = vault;
        _poolId = poolId;

        _pool = _getPoolFromId(poolId);
    }

    function rebalancePool() public {
        require(
            block.timestamp - _lastRebalanceCall >= _MINIMUM_DURATION_BETWEEN_REBALANCE,
            "Minimum time between calls not met"
        );

        if (isPoolPaused()) {
            _pool.setSwapEnabled(true);
        }

        // Updates swap fee from 100% to 0.01%
        _pool.updateSwapFeeGradually(block.timestamp, block.timestamp + _REBALANCE_DURATION, 3e15, 1e14);

        _lastRebalanceCall = block.timestamp;

        emit PoolRebalancing(_lastRebalanceCall, _lastRebalanceCall + _REBALANCE_DURATION);
    }

    function pausePool() public {
        require(_lastRebalanceCall + _REBALANCE_DURATION < block.timestamp, "Pool is still rebalancing");
        require(!isPoolPaused(), "Swaps are already paused");
        _pool.setSwapEnabled(false);
    }

    function isPoolPaused() public view returns (bool) {
        return !_pool.getSwapEnabled();
    }

    function getPoolId() public view returns (bytes32) {
        return _poolId;
    }

    function getVault() public view returns (IVault) {
        return _vault;
    }

    function getPoolTokens() public view returns (IERC20[] memory) {
        (IERC20[] memory tokens, , ) = _vault.getPoolTokens(_poolId);
        return ComposablePoolLib.dropBptFromTokens(tokens);
    }

    /// === Private and Internal ===
    function _getPoolFromId(bytes32 poolId) internal pure returns (IManagedPool) {
        // 12 byte logical shift left to remove the nonce and specialization setting. We don't need to mask,
        // since the logical shift already sets the upper bits to zero.
        return IManagedPool(address(uint256(poolId) >> (12 * 8)));
    }

}
