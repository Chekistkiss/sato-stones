// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {GenesisCandidate, LockDays, RarityTier, Vault} from "../VaultTypes.sol";

/// @notice Genesis race leaderboard and checkpoint eligibility.
library VaultGenesisLib {
    uint256 internal constant BPS = 10_000;

    error InvalidLockDays();

    function offerGenesisCandidate(
        GenesisCandidate[21] storage genesisCandidates,
        uint256 maxGenesis,
        uint256 tokenId,
        uint256 score,
        uint256 count
    ) external returns (uint256 newCount, uint256 rank) {
        if (count < maxGenesis) {
            uint256 pos = count;
            while (pos > 0 && genesisCandidates[pos - 1].score < score) {
                genesisCandidates[pos] = genesisCandidates[pos - 1];
                pos--;
            }
            genesisCandidates[pos] = GenesisCandidate({tokenId: tokenId, score: score});
            return (count + 1, pos + 1);
        }

        if (score <= genesisCandidates[maxGenesis - 1].score) return (count, 0);

        uint256 insertAt = maxGenesis - 1;
        while (insertAt > 0 && genesisCandidates[insertAt - 1].score < score) {
            genesisCandidates[insertAt] = genesisCandidates[insertAt - 1];
            insertAt--;
        }
        genesisCandidates[insertAt] = GenesisCandidate({tokenId: tokenId, score: score});
        return (count, insertAt + 1);
    }

    function markGenesisCheckpointEligible(
        mapping(uint256 => Vault) storage vaults,
        mapping(uint256 => mapping(uint256 => bool)) storage genesisCheckpointEligible,
        uint256 checkpointIdx,
        uint16 activeCount,
        uint256 totalMintedEver,
        uint256 startTokenId
    ) external {
        uint256 n = totalMintedEver;
        uint16 marked;
        for (uint256 id = startTokenId; id < startTokenId + n && marked < activeCount; id++) {
            Vault storage v = vaults[id];
            if (v.isGenesis && v.satoLocked > 0) {
                genesisCheckpointEligible[id][checkpointIdx] = true;
                marked++;
            }
        }
    }

    function computeWeight(
        uint256 peakSato,
        LockDays lockDays,
        bool isGenesis,
        uint256 weightScale,
        uint256 genesisMultiplierBps
    ) external pure returns (uint32) {
        uint256 root = _sqrt(peakSato);
        uint256 w = (root * lockMultiplierBps(lockDays)) / weightScale;
        if (isGenesis) w = (w * genesisMultiplierBps) / BPS;
        if (w > type(uint32).max) w = type(uint32).max;
        return uint32(w);
    }

    function rarityFromWeight(uint32 weight) external pure returns (RarityTier) {
        if (weight >= 250) return RarityTier.Mythic;
        if (weight >= 80) return RarityTier.Rare;
        if (weight >= 25) return RarityTier.Uncommon;
        return RarityTier.Common;
    }

    function lockMultiplierBps(LockDays lockDays) private pure returns (uint256) {
        if (lockDays == LockDays.Thirty) return 10_000;
        if (lockDays == LockDays.Ninety) return 25_000;
        if (lockDays == LockDays.OneEighty) return 50_000;
        if (lockDays == LockDays.ThreeSixtyFive) return 100_000;
        revert InvalidLockDays();
    }

    function _sqrt(uint256 x) private pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}
