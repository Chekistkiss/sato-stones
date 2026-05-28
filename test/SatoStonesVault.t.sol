// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SatoStonesVault} from "../src/SatoStonesVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockVRFCoordinator} from "../src/mocks/MockVRFCoordinator.sol";

contract SatoStonesVaultTest is Test {
    SatoStonesVault public vault;
    MockERC20 public sato;
    MockVRFCoordinator public vrf;

    address public dev = address(0xD3);
    address public user = address(0xB0B);
    address public buyer = address(0xB0C);

    function setUp() public {
        sato = new MockERC20();
        vrf = new MockVRFCoordinator();
        vault = new SatoStonesVault(
            address(sato),
            dev,
            10 ether,
            30 days,
            address(vrf),
            bytes32(uint256(1)),
            1,
            3,
            250_000,
            "ipfs://"
        );
        sato.mint(user, 1_000_000 ether);
        vm.prank(user);
        sato.approve(address(vault), type(uint256).max);
    }

    function test_MintStoresSimplifiedVaultFields() public {
        vm.prank(user);
        uint256 id = vault.mint(500 ether, SatoStonesVault.LockDays.Sixty);
        assertEq(id, 1);
        (uint256 peakSato, uint256 locked,, uint32 weight,, SatoStonesVault.RarityTier rarity, bool redeemed) = vault.vaults(1);
        assertEq(peakSato, 490 ether);
        assertEq(locked, 490 ether);
        assertGt(weight, 0);
        assertEq(uint8(rarity), uint8(SatoStonesVault.RarityTier.Mythic));
        assertFalse(redeemed);
    }

    function test_PreviewMintReturnsWeightAndRarity() public {
        (uint256 peakSato, uint32 weight, SatoStonesVault.RarityTier rarity) =
            vault.previewMint(500 ether, SatoStonesVault.LockDays.Sixty);
        assertEq(peakSato, 490 ether);
        assertGt(weight, 0);
        assertEq(uint8(rarity), uint8(SatoStonesVault.RarityTier.Mythic));
    }

    function test_MintRejectedAfterSingleSeasonEnds() public {
        vm.warp(block.timestamp + vault.SEASON_DURATION());
        vm.prank(user);
        vm.expectRevert(SatoStonesVault.SeasonEnded.selector);
        vault.mint(500 ether, SatoStonesVault.LockDays.Sixty);
    }

    function test_RedeemAfterLock() public {
        vm.prank(user);
        vault.mint(100 ether, SatoStonesVault.LockDays.Fifteen);
        vm.warp(block.timestamp + 16 days);
        vault.finalizeSeason(0);
        uint256 before = sato.balanceOf(user);
        vm.prank(user);
        vault.redeem(1);
        assertGt(sato.balanceOf(user), before);
        (, uint256 locked,,,,, bool redeemed) = vault.vaults(1);
        assertEq(locked, 0);
        assertTrue(redeemed);
        assertEq(vault.ownerOf(1), user);
    }

    function test_EarlyExitBurnsNFT() public {
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Fifteen);
        vm.prank(user);
        vault.earlyExit(1);
        vm.expectRevert();
        vault.ownerOf(1);
    }

    function test_PenaltySplitBps() public {
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Fifteen);

        (uint256 peakSato,,,,,,) = vault.vaults(1);

        uint256 seasonBefore = vault.seasonPool(0);
        uint256 devBefore = vault.devBalance();
        uint256 prizeBefore = vault.prizeFund();
        uint256 deadBefore = sato.balanceOf(vault.DEAD());

        uint256 balBefore = sato.balanceOf(user);
        vm.prank(user);
        vault.earlyExit(1);
        uint256 returned = sato.balanceOf(user) - balBefore;
        uint256 penalty = peakSato - returned;

        assertEq(vault.seasonPool(0) - seasonBefore, (penalty * 5000) / 10_000);
        assertEq(vault.devBalance() - devBefore, (penalty * 200) / 10_000);
        assertEq(vault.prizeFund() - prizeBefore, (penalty * 1500) / 10_000);
        assertEq(sato.balanceOf(vault.DEAD()) - deadBefore, (penalty * 3300) / 10_000);
    }

    function test_CannotRequestDrawWhilePending() public {
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Fifteen);
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Sixty);
        vm.prank(user);
        vault.earlyExit(1);

        vm.warp(block.timestamp + 31 days);
        vault.requestPrizeDraw();

        vm.warp(block.timestamp + 31 days);
        vm.expectRevert(SatoStonesVault.DrawPending.selector);
        vault.requestPrizeDraw();
    }

    function test_RecoverTimedOutPrizeDraw() public {
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Fifteen);
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Sixty);
        vm.prank(user);
        vault.earlyExit(1);

        vm.warp(block.timestamp + 31 days);
        uint256 requestId = vault.requestPrizeDraw();
        uint256 pending = vault.pendingDrawPrize();
        assertGt(pending, 0);

        vm.warp(vault.lastPrizeDrawAt() + vault.PRIZE_DRAW_TIMEOUT() + 1);
        vault.recoverTimedOutPrizeDraw();

        assertEq(vault.pendingDrawPrize(), 0);
        assertEq(vault.pendingDrawRequestId(), 0);
        assertEq(vault.prizeFund(), pending);

        vm.expectRevert(bytes("fulfill failed"));
        vrf.fulfill(requestId, 7);
    }

    function test_PrizeDrawAssignsAndClaimPrize() public {
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Fifteen);
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Sixty);
        vm.prank(user);
        vault.earlyExit(1);

        vm.warp(block.timestamp + 31 days);
        uint256 requestId = vault.requestPrizeDraw();
        uint256 prize = vault.pendingDrawPrize();

        vrf.fulfill(requestId, 0);

        assertEq(vault.pendingPrize(user), prize);
        assertEq(vault.pendingDrawPrize(), 0);
        assertEq(vault.pendingDrawRequestId(), 0);

        uint256 before = sato.balanceOf(user);
        vm.prank(user);
        vault.claimPrize();
        assertEq(sato.balanceOf(user) - before, prize);
        assertEq(vault.pendingPrize(user), 0);
    }

    function test_PrizeDrawUsesRequestTimeOwnerSnapshot() public {
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Fifteen);
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Sixty);
        vm.prank(user);
        vault.earlyExit(1);

        vm.warp(block.timestamp + 31 days);
        vault.finalizeSeason(0);
        uint256 requestId = vault.requestPrizeDraw();
        uint256 prize = vault.pendingDrawPrize();

        vm.prank(user);
        vault.transferFrom(user, buyer, 2);

        vrf.fulfill(requestId, 0);

        assertEq(vault.ownerOf(2), buyer);
        assertEq(vault.pendingPrize(user), prize);
        assertEq(vault.pendingPrize(buyer), 0);
    }

    function test_CannotRequestDrawWithoutEligibleTickets() public {
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Fifteen);
        vm.prank(user);
        vault.earlyExit(1);

        vm.warp(block.timestamp + 31 days);
        uint256 before = vault.prizeFund();
        vault.requestPrizeDraw();
        assertEq(vault.pendingDrawPrize(), 0);
        assertEq(vault.pendingDrawRequestId(), 0);
        assertEq(vault.prizeFund(), before);
    }

    function test_EarlyExitPenaltyCeilsPartialDay() public {
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Fifteen);

        (uint256 peakSato,, uint64 lockEnd,,,,) = vault.vaults(1);
        vm.warp(uint256(lockEnd) - 1);

        uint256 penalty = vault.getEarlyExitPenalty(1);
        assertEq(penalty, (peakSato * 3000 / 10_000) / 15);
        assertGt(penalty, 0);
    }

    function test_RawFulfillRejectsNonCoordinator() public {
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Fifteen);
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Sixty);
        vm.prank(user);
        vault.earlyExit(1);

        vm.warp(block.timestamp + 31 days);
        uint256 requestId = vault.requestPrizeDraw();
        uint256[] memory words = new uint256[](1);
        words[0] = 7;

        vm.expectRevert(SatoStonesVault.OnlyVRFCoordinator.selector);
        vault.rawFulfillRandomWords(requestId, words);
    }

    function test_FifteenDayMintAtT0IsSeasonEligible() public {
        vm.prank(user);
        vault.mint(100 ether, SatoStonesVault.LockDays.Fifteen);

        vm.warp(block.timestamp + 16 days);
        vault.finalizeSeason(0);

        assertEq(vault.snapshotOwner(0, 1), user);
        assertGt(vault.claimableSeasonAmount(0, 1), 0);
    }
}
