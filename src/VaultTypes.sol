// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Shared types for SatoStonesVaultV2 and linked libraries.
enum LockDays {
    Thirty,
    Ninety,
    OneEighty,
    ThreeSixtyFive
}

enum RarityTier {
    Common,
    Uncommon,
    Rare,
    Mythic
}

struct Vault {
    uint256 peakSato;
    uint256 satoLocked;
    uint64 mintTime;
    uint64 lockEnd;
    uint32 weightAtMint;
    LockDays lockDays;
    RarityTier rarity;
    bool isGenesis;
    uint8 genesisRank;
    bool redeemed;
}

struct GenesisCandidate {
    uint256 tokenId;
    uint256 score;
}

struct GenesisCheckpoint {
    uint256 amount;
    uint16 activeCount;
    uint64 timestamp;
}

struct SeasonFinalizeState {
    uint256 distributable;
    uint256 totalEffectiveWeight;
    uint256 cursor;
}
