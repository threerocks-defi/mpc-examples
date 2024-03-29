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
// Gradual weight updates over 7 days for each change
import "@balancer-labs/v2-interfaces/contracts/pool-utils/ILastCreatedPoolFactory.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import "@balancer-labs/v2-pool-utils/contracts/lib/ComposablePoolLib.sol";
import "../interfaces/IManagedPoolFactory.sol";

// solhint-disable not-rely-on-time

contract WeightChangerController {
    using FixedPoint for uint256;
    IERC20[] private _tokens;

    uint256 private constant _REWEIGHT_DURATION = 7 days;

    // Minimum and maximum weight limits
    uint256 private constant _MIN_WEIGHT = 1e16; // 1%
    uint256 private constant _MAX_WEIGHT = 99e16; // 99%

    IVault private immutable _vault;
    bytes32 private immutable _poolId;

    constructor(IVault vault) {
        // Get poolId from the factory
        bytes32 poolId = IManagedPool(ILastCreatedPoolFactory(msg.sender).getLastCreatedPool()).getPoolId();

        // Set the global tokens variables
        (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
        _setTokens(tokens);

        _vault = vault;
        _poolId = poolId;
    }

    /**
     * @dev Starts the gradual reweight process to bring the token's weights to 50/50.
     * @dev Gradual reweight will start when this function is called and take _REWEIGHT_DURATION to complete.
     */
    function make5050() public {
        uint256[] memory newWeights = new uint256[](2);
        newWeights[0] = 50e16;
        newWeights[1] = 50e16;
        _updateWeights(block.timestamp, block.timestamp + _REWEIGHT_DURATION, getTokens(), newWeights);
    }

    /**
     * @dev Starts the gradual reweight process to bring the token's weights to 80/20.
     * @dev Gradual reweight will start when this function is called and take _REWEIGHT_DURATION to complete.
     */
    function make8020() public {
        uint256[] memory newWeights = new uint256[](2);
        newWeights[0] = 80e16;
        newWeights[1] = 20e16;
        _updateWeights(block.timestamp, block.timestamp + _REWEIGHT_DURATION, getTokens(), newWeights);
    }

    /**
     * @dev Starts the gradual reweight process to bring the token's weights to 99/01.
     * @dev Gradual reweight will start when this function is called and take _REWEIGHT_DURATION to complete.
     */
    function make9901() public {
        uint256[] memory newWeights = new uint256[](2);
        newWeights[0] = 99e16;
        newWeights[1] = 1e16;
        _updateWeights(block.timestamp, block.timestamp + _REWEIGHT_DURATION, getTokens(), newWeights);
    }

    // === Public Getters ===
    function getMaximumWeight() public pure returns (uint256) {
        return _MAX_WEIGHT;
    }

    function getMinimumWeight() public pure returns (uint256) {
        return _MIN_WEIGHT;
    }

    function getCurrentWeights() public view returns (uint256[] memory) {
        return _getPool().getNormalizedWeights();
    }

    function getReweightDuration() public pure returns (uint256) {
        return _REWEIGHT_DURATION;
    }

    function getTokens() public view returns (IERC20[] memory) {
        return _tokens;
    }

    function getPoolId() public view returns (bytes32) {
        return _poolId;
    }

    function getVault() public view returns (IVault) {
        return _vault;
    }

    /// === Private and Internal ===
    function _checkWeight(uint256 normalizedWeight) internal pure {
        require(normalizedWeight >= _MIN_WEIGHT, "Weight under minimum");
        require(normalizedWeight <= _MAX_WEIGHT, "Weight over maximum");
    }

    function _checkWeights(uint256[] memory normalizedWeights) internal pure {
        uint256 normalizedSum = 0;
        for (uint256 i = 0; i < normalizedWeights.length; i++) {
            _checkWeight(normalizedWeights[i]);
            normalizedSum = normalizedSum.add(normalizedWeights[i]);
        }

        require(normalizedSum == FixedPoint.ONE, "Weights must sum to one");
    }

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

    /**
     * @dev Updates the weights of the managed pool.
     * @param startTime The timestamp, in seconds, at when the gradual weight update process starts.
     * @param endTime The timestamp, in seconds, at when the gradual weight update process is complete.
     * @param tokens An array of tokens, IERC20, that make up the managed pool.
     * @param weights The desired end weights of the pool tokens. Must correspond with the tokens parameter.
     */
    function _updateWeights(
        uint256 startTime,
        uint256 endTime,
        IERC20[] memory tokens,
        uint256[] memory weights
    ) internal {
        _checkWeights(weights);
        _getPool().updateWeightsGradually(startTime, endTime, tokens, weights);
    }
}
