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

// solhint-disable not-rely-on-time

contract EbuRebalancerController {
    IVault private immutable _vault;
    bytes32 private immutable _poolId;
    IERC20[] private _tokens;

    uint256 private constant _MINIMUM_DURATION_BETWEEN_REBALANCE = 30 days;
    uint256 private constant _REBALANCE_DURATION = 7 days;
    uint256 private constant _MIN_PAUSE_DURATION = 7 days;

    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 95e16; // 95%
    uint256 private immutable _minSwapFeePercentage;

    uint256 private _lastPauseCall;
    uint256 private _lastRebalanceCall;

    event PoolRebalancing(uint256 indexed startTime, uint256 endTime);

    constructor(IVault vault, uint256 minSwapFeePercentage) {
        // Get poolId from the factory.
        bytes32 poolId = IManagedPool(ILastCreatedPoolFactory(msg.sender).getLastCreatedPool()).getPoolId();

        // Set the global tokens variables
        (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
        _setTokens(tokens);

        // Store Vault and poolId.
        _vault = vault;
        _poolId = poolId;

        // Set minimum swap fee percentage.
        _minSwapFeePercentage = minSwapFeePercentage;
    }

    function rebalancePool() public {
        require(
            block.timestamp - _lastRebalanceCall >= _MINIMUM_DURATION_BETWEEN_REBALANCE,
            "Minimum time between calls not met"
        );
        require(block.timestamp - _lastPauseCall >= _MIN_PAUSE_DURATION, "Pool must be paused for at least 7 days");
        require(isPoolPaused(), "Pool must be paused to call rebalance");

        IManagedPool pool = _getPool();

        pool.setSwapEnabled(true);

        // Updates swap fee from max fee (near 100%) to min fee (near 0%).```
        pool.updateSwapFeeGradually(
            block.timestamp,
            block.timestamp + _REBALANCE_DURATION,
            _MAX_SWAP_FEE_PERCENTAGE,
            _minSwapFeePercentage
        );

        _lastRebalanceCall = block.timestamp;

        emit PoolRebalancing(block.timestamp, block.timestamp + _REBALANCE_DURATION);
    }

    function pausePool() public {
        require(block.timestamp - _lastRebalanceCall >= _REBALANCE_DURATION, "Pool is still rebalancing");
        require(!isPoolPaused(), "Swaps are already paused");

        _getPool().setSwapEnabled(false);
        _lastPauseCall = block.timestamp;
    }

    function isPoolPaused() public view returns (bool) {
        return !_getPool().getSwapEnabled();
    }

    function getPoolId() public view returns (bytes32) {
        return _poolId;
    }

    function getVault() public view returns (IVault) {
        return _vault;
    }

    function getTokens() public view returns (IERC20[] memory) {
        return _tokens;
    }

    /// === Private and Internal ===
    function _getPoolFromId(bytes32 poolId) internal pure returns (IManagedPool) {
        // 12 byte logical shift left to remove the nonce and specialization setting. We don't need to mask,
        // since the logical shift already sets the upper bits to zero.
        return IManagedPool(address(uint256(poolId) >> (12 * 8)));
    }

    function _getPool() internal view returns (IManagedPool) {
        return _getPoolFromId(getPoolId());
    }

    function _setTokens(IERC20[] memory tokens) internal {
        _tokens = ComposablePoolLib.dropBptFromTokens(tokens);
    }
}
