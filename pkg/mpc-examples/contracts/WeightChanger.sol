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

// This contract shows an example of how a managed pool controller can modify a pools weight
// gradual weight updates over 7 days for each change
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault";

import "@orbcollective/shared-dependencies/contacts/TestToken.sol";
import "@orbcollective/shared-dependencies/contacts/TestWETH.sol";

contract WeightChanger {
    // Assets WETH/USDC
    IERC20[] private _tokens;

    // TODO: Maybe delete these
    // TODO: Find a function to get currentTokenWeights of a pool
    uint256 private _currentWETHWeight;
    uint256 private _currentUSDCWeight;

    // Rebalance duration
    uint256 private constant _REBALANCE_DURATION = 7 days;

    // Minimum and maximum weight limits
    uint256 private constant _MIN_WEIGHT = 1e16; // 1%
    uint256 private constant _MAX_WEIGHT = 99e16; // 99%

    IVault private immutable _vault;
    bytes32 private immutable _poolId;
    IManagedPool private immutable _pool;

    constructor(IVault vault, bytes32 poolId, address weth, address usdc, uint256[] startingWeights) {
        // Verify that this is a real Vault and the pool is registered - this call will revert if not.
        vault.getPool(poolId);

        _vault = vault;
        _poolId = poolId;
        _pool = _getPoolFromId(poolId);

        _tokens.push(IERC20(weth));
        _tokens.push(IERC20(usdc));

        // TODO: Maybe delete these
        _currentWETHWeight = startingWeights[0];
        _currentUSDCWeight = startingWeights[1];
    }

    function make5050() public {
        uint256 fiftyFifty = [50e16, 50e16];
        _updateWeights(pool, block.timestamp, block.timestamp + duration, _tokens, fiftyFifty);
    }

    function make8020() public {
        uint256 eightyTwenty = [80e16, 20e16];
        _updateWeights(pool, block.timestamp, block.timestamp + duration, _tokens, eightyTwenty);
    }

    function make9901() public {
        uint256 eightyTwenty = [99e16, 1e16];
        _updateWeights(pool, block.timestamp, block.timestamp + duration, _tokens, eightyTwenty);
    }

    // Returns the time until weights are updated
    function _updateWeights(
        address pool,
        uint256 startBlock,
        uint256 endBlock,
        IERC20[] tokens,
        uint256[] weights
    ) internal returns (uint256) {
        pool.updateWeightsGradually(startTime, endTime, tokens, endWeights);
        return endTime - startTime;
    }

    // === Public Getters ===
    function getMaximumWeight() public pure override returns (uint256) {
        return _MAX_WEIGHT;
    }

    function getMinimumWeight() public pure override returns (uint256) {
        return _MIN_WEIGHT;
    }

    /// === Private and Internal ===
    function _getPoolFromId(bytes32 poolId) internal pure override returns (IManagedPool) {
        // 12 byte logical shift left to remove the nonce and specialization setting. We don't need to mask,
        // since the logical shift already sets the upper bits to zero.
        return IManagedPool(address(uint256(poolId) >> (12 * 8)));
    }
}
