// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Season finalize: minter wallet cap and per-token claim amounts.
library VaultSeasonLib {
    uint256 internal constant BPS = 10_000;

    function applyMinterCapAndSetClaims(
        mapping(uint256 => mapping(uint256 => uint256)) storage weightInSeason,
        mapping(uint256 => mapping(uint256 => uint256)) storage claimAmount,
        mapping(uint256 => address) storage originalMinter,
        uint256 seasonId,
        uint256 distributable,
        uint256 totalWeight,
        uint256 totalMintedEver,
        uint256 startTokenId,
        uint256 walletCapBps
    ) external returns (uint256 totalAllocated) {
        uint256 n = totalMintedEver;
        address[] memory minters = new address[](n);
        uint256[] memory minterRaw = new uint256[](n);
        uint256 minterCount;

        for (uint256 id = startTokenId; id < startTokenId + n; id++) {
            uint256 w = weightInSeason[seasonId][id];
            if (w == 0) continue;
            address m = originalMinter[id];
            uint256 raw = (distributable * w) / totalWeight;
            uint256 idx = _indexOfAddress(minters, minterCount, m);
            if (idx == type(uint256).max) {
                minters[minterCount] = m;
                minterRaw[minterCount] = raw;
                minterCount++;
            } else {
                minterRaw[idx] += raw;
            }
        }

        uint256 minterCap = (distributable * walletCapBps) / BPS;

        for (uint256 id = startTokenId; id < startTokenId + n; id++) {
            uint256 w = weightInSeason[seasonId][id];
            if (w == 0) continue;
            address m = originalMinter[id];
            uint256 raw = (distributable * w) / totalWeight;
            uint256 idx = _indexOfAddress(minters, minterCount, m);
            uint256 mr = minterRaw[idx];
            uint256 paid = raw;
            if (mr > minterCap) paid = (raw * minterCap) / mr;
            claimAmount[seasonId][id] = paid;
            totalAllocated += paid;
        }
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
