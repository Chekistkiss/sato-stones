// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vault} from "../VaultTypes.sol";

/// @notice Prize draw: eligible minter snapshot and weighted winner selection.
library VaultLotteryLib {
    uint256 internal constant BPS = 10_000;

    function snapshotDrawMinters(
        mapping(uint256 => Vault) storage vaults,
        mapping(uint256 => address) storage originalMinter,
        address[] storage drawMinters,
        uint256[] storage drawMinterWeights,
        uint256 totalMintedEver,
        uint256 startTokenId,
        uint256 lotteryWalletCapBps
    ) external returns (uint256 totalWeight) {

        uint256 n = totalMintedEver;
        address[] memory minters = new address[](n);
        uint256[] memory weights = new uint256[](n);
        uint256 count;

        for (uint256 id = startTokenId; id < startTokenId + n; id++) {
            Vault storage v = vaults[id];
            if (v.satoLocked == 0 || block.timestamp >= v.lockEnd) continue;
            address m = originalMinter[id];
            uint256 w = v.weightAtMint;
            uint256 idx = _indexOfAddress(minters, count, m);
            if (idx == type(uint256).max) {
                minters[count] = m;
                weights[count] = w;
                count++;
            } else {
                weights[idx] += w;
            }
        }

        if (count == 0) return 0;

        uint256 totalRaw;
        for (uint256 i; i < count; i++) totalRaw += weights[i];

        uint256 cap = (totalRaw * lotteryWalletCapBps) / BPS;
        uint256 cumulative;
        for (uint256 i; i < count; i++) {
            uint256 capped = weights[i];
            if (capped > cap) capped = cap;
            if (capped == 0) continue;
            cumulative += capped;
            drawMinters.push(minters[i]);
            drawMinterWeights.push(cumulative);
        }
        return cumulative;
    }

    function drawWinner(
        address[] storage drawMinters,
        uint256[] storage drawMinterWeights,
        uint256 randomWord,
        uint256 totalWeight
    ) external returns (address winner, uint256 removedWeight) {
        uint256 len = drawMinters.length;
        if (len == 0 || totalWeight == 0) return (address(0), 0);

        uint256 roll = randomWord % totalWeight;
        uint256 idx = _drawWinnerIndex(drawMinterWeights, roll);
        winner = drawMinters[idx];
        removedWeight = idx == 0 ? drawMinterWeights[0] : drawMinterWeights[idx] - drawMinterWeights[idx - 1];

        for (uint256 i = idx; i < len - 1; i++) {
            drawMinters[i] = drawMinters[i + 1];
            drawMinterWeights[i] = drawMinterWeights[i + 1] - removedWeight;
        }
        drawMinters.pop();
        drawMinterWeights.pop();
    }

    function _drawWinnerIndex(uint256[] storage drawMinterWeights, uint256 roll)
        private
        view
        returns (uint256)
    {
        uint256 lo;
        uint256 hi = drawMinterWeights.length;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            if (roll < drawMinterWeights[mid]) hi = mid;
            else lo = mid + 1;
        }
        return lo;
    }

    function _indexOfAddress(
        address[] memory addrs,
        uint256 count,
        address target
    ) private pure returns (uint256) {
        for (uint256 i; i < count; i++) {
            if (addrs[i] == target) return i;
        }
        return type(uint256).max;
    }
}
