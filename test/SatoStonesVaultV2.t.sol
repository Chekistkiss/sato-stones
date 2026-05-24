// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SatoStonesVaultV2} from "../src/SatoStonesVaultV2.sol";
import {LockDays} from "../src/VaultTypes.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockVRFCoordinator} from "../src/mocks/MockVRFCoordinator.sol";

contract SatoStonesVaultV2Test is Test {
    SatoStonesVaultV2 public vault;
    MockERC20 public sato;
    MockVRFCoordinator public vrf;

    address public dev = address(0xD3);
    address public user = address(0xB0B);
    address public user2 = address(0xB0C);
    address public user3 = address(0xB0D);

    function setUp() public {
        sato = new MockERC20();
        vrf = new MockVRFCoordinator();
        vault = new SatoStonesVaultV2(
            address(sato),
            dev,
            10 ether,
            30 days,
            address(vrf),
            bytes32(uint256(1)),
            1,
            3,
            750_000,
            "ipfs://"
        );
        sato.mint(user, 10_000_000 ether);
        sato.mint(user2, 10_000_000 ether);
        sato.mint(user3, 10_000_000 ether);
        vm.prank(user);
        sato.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        sato.approve(address(vault), type(uint256).max);
        vm.prank(user3);
        sato.approve(address(vault), type(uint256).max);
    }


    function _finalizeSeasonFull(uint256 seasonId) internal {
        uint256 n = vault.totalMintedEver();
        if (n == 0) {
            vm.expectRevert();
            vault.finalizeSeasonClose(seasonId);
            return;
        }
        vault.finalizeSeasonChunk(seasonId, 1, n);
        vault.finalizeSeasonClose(seasonId);
    }

    function test_MintAndPreview() public {
        vm.prank(user);
        uint256 id = vault.mint(100 ether, LockDays.Thirty);
        assertEq(id, 1);
        (
            uint256 peak,
            uint32 w0,
            uint32 w1,
            ,
            ,
            ,
            bool raceOpen
        ) = vault.previewMint(100 ether, LockDays.Thirty);
        assertEq(peak, 96 ether);
        assertGt(w1, w0);
        assertTrue(raceOpen);
        assertEq(vault.sumLocked(), 96 ether);
    }

    function test_MinMintProducesWeight() public {
        vm.prank(user);
        vault.mint(50 ether, LockDays.Thirty);
        (,,,,uint32 weight,,,,,) = vault.vaults(1);
        assertGt(weight, 0);
    }

    function test_MintFeeSplit() public {
        uint256 devBefore = vault.devBalance();
        uint256 prizeBefore = vault.prizeFund();
        uint256 deadBefore = sato.balanceOf(vault.DEAD());

        vm.prank(user);
        vault.mint(1000 ether, LockDays.Thirty);

        uint256 fee = (1000 ether * 400) / 10_000;
        assertEq(vault.devBalance() - devBefore, (fee * 3500) / 10_000);
        assertEq(vault.prizeFund() - prizeBefore, (fee * 1000) / 10_000);
        assertEq(sato.balanceOf(vault.DEAD()) - deadBefore, (fee * 500) / 10_000);
    }

    function test_RedeemAfterLock() public {
        vm.prank(user);
        vault.mint(100 ether, LockDays.Thirty);
        vm.warp(block.timestamp + 31 days);
        uint256 before = sato.balanceOf(user);
        vm.prank(user);
        vault.redeem(1);
        assertGt(sato.balanceOf(user), before);
        assertEq(vault.sumLocked(), 0);
        (, uint256 satoLocked,,,,,,,, bool redeemed) = vault.vaults(1);
        assertEq(satoLocked, 0);
        assertTrue(redeemed);
    }

    function test_EarlyExitBurnsNFT() public {
        vm.prank(user);
        vault.mint(1000 ether, LockDays.Thirty);
        vm.prank(user);
        vault.earlyExit(1);
        vm.expectRevert();
        vault.ownerOf(1);
    }

    function test_PenaltySplitBps() public {
        vm.prank(user);
        vault.mint(1000 ether, LockDays.Thirty);
        (uint256 peakSato,,,,,,,,,) = vault.vaults(1);

        uint256 poolBefore = vault.seasonPool(0);
        uint256 devBefore = vault.devBalance();
        uint256 prizeBefore = vault.prizeFund();
        uint256 deadBefore = sato.balanceOf(vault.DEAD());

        uint256 balBefore = sato.balanceOf(user);
        vm.prank(user);
        vault.earlyExit(1);
        uint256 returned = sato.balanceOf(user) - balBefore;
        uint256 penalty = peakSato - returned;

        assertEq(vault.seasonPool(0) - poolBefore, (penalty * 6500) / 10_000);
        assertEq(vault.devBalance() - devBefore, (penalty * 1000) / 10_000);
        assertEq(vault.prizeFund() - prizeBefore, (penalty * 2000) / 10_000);
        assertEq(sato.balanceOf(vault.DEAD()) - deadBefore, (penalty * 500) / 10_000);
    }

    function test_PenaltyFloorOnLastPartialDay() public {
        vm.prank(user);
        vault.mint(1000 ether, LockDays.Thirty);
        (,,, uint64 lockEnd,,,,,,) = vault.vaults(1);
        vm.warp(uint256(lockEnd) - 1);
        uint256 penalty = vault.getEarlyExitPenalty(1);
        assertGt(penalty, 0);
        assertEq(penalty, (1000 ether * 96 / 100 * 500) / 10_000);
    }

    function test_GenesisCandidateAndFinalize() public {
        vm.prank(user);
        vault.mint(5000 ether, LockDays.ThreeSixtyFive);

        (, uint256 count) = vault.genesisLeaderboard();
        assertEq(count, 1);

        vm.warp(vault.t0() + 30 days + 1);
        vault.finalizeGenesis();
        assertTrue(vault.genesisFinalized());
        (,,,,,,, bool isGenesis, uint8 genesisRank,) = vault.vaults(1);
        assertTrue(isGenesis);
        assertEq(genesisRank, 1);
    }

    function test_GenesisCannotEarlyExit() public {
        vm.prank(user);
        vault.mint(5000 ether, LockDays.ThreeSixtyFive);
        vm.warp(vault.t0() + 30 days + 1);
        vault.finalizeGenesis();
        vm.expectRevert(SatoStonesVaultV2.GenesisCannotExit.selector);
        vm.prank(user);
        vault.earlyExit(1);
    }

    function test_RepledgeAfterRedeem() public {
        vm.prank(user);
        vault.mint(5000 ether, LockDays.ThreeSixtyFive);
        vm.warp(vault.t0() + 30 days + 1);
        vault.finalizeGenesis();
        vm.warp(block.timestamp + 365 days + 1);
        vm.prank(user);
        vault.redeem(1);
        vm.prank(user);
        vault.repledge(1, 500 ether, LockDays.Ninety);
        (, uint256 satoLocked,,,,,,,, bool redeemed) = vault.vaults(1);
        assertGt(satoLocked, 0);
        assertFalse(redeemed);
    }

    function test_SeasonFinalizeAndClaim() public {
        vm.prank(user);
        vault.mint(500 ether, LockDays.Ninety);
        vm.warp(31 days);
        _finalizeSeasonFull(0);
        assertTrue(vault.seasonFinalized(0));
        uint256 claim = vault.claimAmount(0, 1);
        assertGt(claim, 0);
        uint256 before = sato.balanceOf(user);
        vm.prank(user);
        vault.claimSeason(0, 1);
        assertEq(sato.balanceOf(user) - before, claim);
    }

    function test_WalletCapByOriginalMinter() public {
        vm.startPrank(user);
        vault.mint(2000 ether, LockDays.Ninety);
        vault.mint(2000 ether, LockDays.Ninety);
        vm.stopPrank();

        vm.warp(31 days);
        _finalizeSeasonFull(0);

        uint256 c1 = vault.claimAmount(0, 1);
        uint256 c2 = vault.claimAmount(0, 2);
        uint256 pool = (2000 ether * 400 / 10_000) * 5000 / 10_000 * 2;
        uint256 cap = (pool * 800) / 10_000;
        assertEq(c1 + c2, cap);
    }

    function test_TransferLockoutReverts() public {
        vm.prank(user);
        vault.mint(500 ether, LockDays.Thirty);
        uint256 end = vault.seasonEnd(0);
        vm.warp(end - 12 hours);
        vm.prank(user);
        vm.expectRevert(SatoStonesVaultV2.SeasonTransferLocked.selector);
        vault.transferFrom(user, user2, 1);
    }

    function test_SeasonSnapshotUsesLastTransferOwner() public {
        vm.prank(user);
        vault.mint(500 ether, LockDays.Ninety);
        uint256 end = vault.seasonEnd(0);
        vm.warp(end - 2 days);
        vm.prank(user);
        vault.transferFrom(user, user2, 1);
        vm.warp(end + 1);
        _finalizeSeasonFull(0);
        assertEq(vault.snapshotOwner(0, 1), user2);
        uint256 amt = vault.claimAmount(0, 1);
        vm.prank(user2);
        vault.claimSeason(0, 1);
        assertGt(amt, 0);
        assertEq(sato.balanceOf(user2), 10_000_000 ether + amt);
    }

    function test_PrizeDrawTopThree() public {
        vm.prank(user3);
        vault.mint(1000 ether, LockDays.Ninety);
        vm.prank(user3);
        vault.earlyExit(1);

        vm.prank(user);
        vault.mint(1000 ether, LockDays.Ninety);
        vm.prank(user2);
        vault.mint(1000 ether, LockDays.Ninety);

        vm.warp(block.timestamp + 31 days);
        uint256 requestId = vault.requestPrizeDraw();
        uint256 prize = vault.pendingDrawPrize();

        vrf.fulfillWords(requestId, 0, 1, 2);

        uint256 uPrize = vault.pendingPrize(user);
        uint256 u2Prize = vault.pendingPrize(user2);
        assertEq(uPrize + u2Prize + vault.prizeFund(), prize);
        assertGt(uPrize, 0);
        assertGt(u2Prize, 0);
    }

    function test_RecoverTimedOutPrizeDraw() public {
        vm.prank(user);
        vault.mint(1000 ether, LockDays.Ninety);
        vm.prank(user2);
        vault.mint(1000 ether, LockDays.Ninety);
        vm.prank(user);
        vault.earlyExit(1);

        vm.warp(block.timestamp + 31 days);
        vault.requestPrizeDraw();
        uint256 pending = vault.pendingDrawPrize();
        vm.warp(vault.lastPrizeDrawAt() + vault.PRIZE_DRAW_TIMEOUT() + 1);
        vault.recoverTimedOutPrizeDraw();
        assertEq(vault.prizeFund(), pending);
    }

    function test_SponsorSeason() public {
        vm.prank(user);
        vault.sponsorSeason(0, 1000 ether, "partner");
        assertEq(vault.seasonPool(0), 900 ether);
        assertEq(vault.devBalance(), 100 ether);
    }

    function test_DistributeRoyalty() public {
        sato.mint(address(vault), 50 ether);
        uint256 poolBefore = vault.seasonPool(0);
        uint256 devBefore = vault.devBalance();
        vault.distributeRoyalty();
        assertEq(vault.seasonPool(0) - poolBefore, (50 ether * 4000) / 10_000);
        assertEq(vault.devBalance() - devBefore, (50 ether * 4000) / 10_000);
    }

    function test_AccountingSolvencyAfterMint() public {
        vm.prank(user);
        vault.mint(1000 ether, LockDays.Ninety);
        assertGe(sato.balanceOf(address(vault)), vault.accountingLiabilities());
    }

    function test_SupportsEIP2981() public view {
        assertTrue(vault.supportsInterface(0x2a55205a));
    }

    function test_RoyaltyInfo() public view {
        (address receiver, uint256 amt) = vault.royaltyInfo(1, 1000 ether);
        assertEq(receiver, address(vault));
        assertEq(amt, 50 ether);
    }

    function test_CloseMissedSeason() public {
        vm.prank(user);
        vault.mint(100 ether, LockDays.Thirty);
        vm.warp(vault.seasonEnd(0) + vault.FINALIZE_GRACE_PERIOD() + 1);
        vault.closeMissedSeason(0);
        assertTrue(vault.seasonClosed(0));
        assertGt(vault.undistributedCarry(), 0);
    }

    function test_Fuzz_PenaltyNeverExceedsPeak(uint256 gross, uint8 lockIdx, uint256 warpSecs)
        public
    {
        gross = bound(gross, 50 ether, 5000 ether);
        lockIdx = uint8(bound(lockIdx, 0, 3));
        LockDays lock = LockDays(lockIdx);

        vm.prank(user);
        uint256 id = vault.mint(gross, lock);
        (uint256 peakSato,, uint64 lockEnd,,,,,,,) = vault.vaults(id);

        uint256 lockSecs = lock == LockDays.Thirty
            ? 30 days
            : lock == LockDays.Ninety
                ? 90 days
                : lock == LockDays.OneEighty ? 180 days : 365 days;

        warpSecs = bound(warpSecs, 1, lockSecs - 1);
        vm.warp(block.timestamp + warpSecs);

        uint256 penalty = vault.getEarlyExitPenalty(id);
        assertLe(penalty, peakSato);
        assertGe(penalty, (peakSato * 500) / 10_000);
    }
}
