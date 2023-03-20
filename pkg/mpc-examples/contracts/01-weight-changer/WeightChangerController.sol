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

        // Verify that this is a real Vault and the pool is registered - this call will revert if not.
        vault.getPool(poolId);

        // Set the global tokens variables
        (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
        _setTokens(tokens);

        _vault = vault;
        _poolId = poolId;
    }

    function make5050() public {
        uint256[] memory fiftyFifty = new uint256[](2);
        fiftyFifty[0] = 50e16;
        fiftyFifty[1] = 50e16;
        _updateWeights(block.timestamp, block.timestamp + _REWEIGHT_DURATION, getTokens(), fiftyFifty);
    }

    function make8020() public {
        uint256[] memory eightyTwenty = new uint256[](2);
        eightyTwenty[0] = 80e16;
        eightyTwenty[1] = 20e16;
        _updateWeights(block.timestamp, block.timestamp + _REWEIGHT_DURATION, getTokens(), eightyTwenty);
    }

    function make9901() public {
        uint256[] memory nintynineOne = new uint256[](2);
        nintynineOne[0] = 99e16;
        nintynineOne[1] = 1e16;
        _updateWeights(block.timestamp, block.timestamp + _REWEIGHT_DURATION, getTokens(), nintynineOne);
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
    function _getPoolFromId(bytes32 poolId) internal pure returns (IManagedPool) {
        // 12 byte logical shift left to remove the nonce and specialization setting. We don't need to mask,
        // since the logical shift already sets the upper bits to zero.
        return IManagedPool(address(uint256(poolId) >> (12 * 8)));
    }

    function _getPool() internal view returns (IManagedPool) {
        return _getPoolFromId(_poolId);
    }

    function _setTokens(IERC20[] memory tokens) internal {
        _tokens = ComposablePoolLib.dropBptFromTokens(tokens);
    }

    // Returns the time until weights are updated
    function _updateWeights(
        uint256 startTime,
        uint256 endTime,
        IERC20[] memory tokens,
        uint256[] memory weights
    ) internal returns (uint256) {
        _verifyWeights(weights);
        _getPool().updateWeightsGradually(startTime, endTime, tokens, weights);
        return endTime - startTime;
    }

    function _verifyWeight(uint256 normalizedWeight) internal pure returns (uint256) {
        require(normalizedWeight >= _MIN_WEIGHT, "Weight less than minimum requirement");
        require(normalizedWeight <= _MAX_WEIGHT, "Weight greater than maximum requirement");
        return normalizedWeight;
    }

    function _verifyWeights(uint256[] memory normalizedWeights) internal pure returns (uint256[] memory) {
        uint256 normalizedSum = 0;
        for (uint256 i = 0; i < normalizedWeights.length; i++) {
            normalizedSum = normalizedSum.add(_verifyWeight(normalizedWeights[i]));
        }

        require(normalizedSum == FixedPoint.ONE, "Weights must sum to one");

        return normalizedWeights;
    }
}
