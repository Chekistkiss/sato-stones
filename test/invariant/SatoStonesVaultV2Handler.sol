// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {SatoStonesVaultV2} from "../../src/SatoStonesVaultV2.sol";
import {LockDays} from "../../src/VaultTypes.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Stateful fuzz handler for SatoStonesVaultV2 invariant tests.
contract SatoStonesVaultV2Handler is CommonBase, StdUtils {
    SatoStonesVaultV2 public immutable vault;
    MockERC20 public immutable sato;

    address[] internal _actors;
    uint256[] internal _ownedTokenIds;
    mapping(address => uint256[]) internal _actorTokens;

    constructor(SatoStonesVaultV2 vault_, MockERC20 sato_) {
        vault = vault_;
        sato = sato_;
        for (uint256 i; i < 12; i++) {
            address actor = address(uint160(0xA000 + i));
            _actors.push(actor);
            sato.mint(actor, 8_000_000 ether);
            vm.prank(actor);
            sato.approve(address(vault), type(uint256).max);
        }
    }

    function mint(uint256 actorSeed, uint256 grossSeed, uint8 lockSeed) external {
        address actor = _actors[bound(actorSeed, 0, _actors.length - 1)];
        if (vault.totalMintedEver() >= vault.MAX_SUPPLY()) return;
        if (vault.walletMintCount(actor) >= vault.MAX_MINTS_PER_WALLET()) return;

        uint256 gross = bound(grossSeed, vault.MIN_GROSS(), vault.maxGrossForMint());
        LockDays lock = LockDays(bound(lockSeed, 0, 3));

        vm.prank(actor);
        try vault.mint(gross, lock) returns (uint256 tokenId) {
            _ownedTokenIds.push(tokenId);
            _actorTokens[actor].push(tokenId);
        } catch {}
    }

    function earlyExit(uint256 actorSeed, uint256 tokenSeed) external {
        address actor = _actors[bound(actorSeed, 0, _actors.length - 1)];
        uint256[] storage ids = _actorTokens[actor];
        if (ids.length == 0) return;

        uint256 tokenId = ids[bound(tokenSeed, 0, ids.length - 1)];
        if (vault.ownerOf(tokenId) != actor) return;

        vm.prank(actor);
        try vault.earlyExit(tokenId) {
            _removeToken(tokenId);
        } catch {}
    }

    function redeem(uint256 actorSeed, uint256 tokenSeed) external {
        address actor = _actors[bound(actorSeed, 0, _actors.length - 1)];
        uint256[] storage ids = _actorTokens[actor];
        if (ids.length == 0) return;

        uint256 tokenId = ids[bound(tokenSeed, 0, ids.length - 1)];
        if (vault.ownerOf(tokenId) != actor) return;

        (,,, uint64 lockEnd,,,,,,) = vault.vaults(tokenId);
        if (block.timestamp < lockEnd) {
            vm.warp(lockEnd + 1);
        }

        vm.prank(actor);
        try vault.redeem(tokenId) {} catch {}
    }

    function warpTime(uint256 secondsSeed) external {
        uint256 jump = bound(secondsSeed, 1 hours, 20 days);
        vm.warp(block.timestamp + jump);
    }

    function finalizePastSeason(uint256 seasonSeed) external {
        uint256 season = bound(seasonSeed, 0, vault.currentSeasonId());
        if (vault.seasonFinalized(season) || vault.seasonClosed(season)) return;
        if (block.timestamp < vault.seasonEnd(season)) {
            vm.warp(vault.seasonEnd(season) + 1);
        }
        if (block.timestamp > vault.seasonEnd(season) + vault.FINALIZE_GRACE_PERIOD()) return;
        uint256 n = vault.totalMintedEver();
        if (n > 0) {
            try vault.finalizeSeasonChunk(season, 1, n) {} catch {}
        }
        try vault.finalizeSeasonClose(season) {} catch {}
    }

    function claimSeason(uint256 actorSeed, uint256 tokenSeed, uint256 seasonSeed) external {
        address actor = _actors[bound(actorSeed, 0, _actors.length - 1)];
        uint256[] storage ids = _actorTokens[actor];
        if (ids.length == 0) return;

        uint256 tokenId = ids[bound(tokenSeed, 0, ids.length - 1)];
        uint256 season = bound(seasonSeed, 0, vault.currentSeasonId());
        if (!vault.seasonFinalized(season)) return;
        if (vault.snapshotOwner(season, tokenId) != actor) return;

        vm.prank(actor);
        try vault.claimSeason(season, tokenId) {} catch {}
    }

    function donateRoyalty(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 1 ether, 500 ether);
        sato.mint(address(vault), amount);
        try vault.distributeRoyalty() {} catch {}
    }

    function _removeToken(uint256 tokenId) internal {
        uint256 len = _ownedTokenIds.length;
        for (uint256 i; i < len; i++) {
            if (_ownedTokenIds[i] == tokenId) {
                _ownedTokenIds[i] = _ownedTokenIds[len - 1];
                _ownedTokenIds.pop();
                break;
            }
        }
        for (uint256 a; a < _actors.length; a++) {
            uint256[] storage ids = _actorTokens[_actors[a]];
            uint256 n = ids.length;
            for (uint256 j; j < n; j++) {
                if (ids[j] == tokenId) {
                    ids[j] = ids[n - 1];
                    ids.pop();
                    return;
                }
            }
        }
    }
}
