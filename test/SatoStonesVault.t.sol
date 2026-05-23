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

    function test_MintGenesis() public {
        vm.prank(user);
        uint256 id = vault.mint(500 ether, SatoStonesVault.LockDays.Sixty);
        assertEq(id, 1);
        (,,,,,, bool isGenesis, uint8 rank,) = vault.vaults(1);
        assertTrue(isGenesis);
        assertEq(rank, 1);
    }

    function test_PreviewGenesisAt500Gross() public {
        (,, , bool wouldBeGenesis) =
            vault.previewMint(500 ether, SatoStonesVault.LockDays.Sixty, true);
        assertTrue(wouldBeGenesis);
    }

    function test_MintNoGenesisBelow500() public {
        vm.prank(user);
        vault.mint(300 ether, SatoStonesVault.LockDays.Fifteen);
        (,,,,,, bool isGenesis,,) = vault.vaults(1);
        assertFalse(isGenesis);
    }

    function test_RedeemAfterLock() public {
        vm.prank(user);
        vault.mint(100 ether, SatoStonesVault.LockDays.Fifteen);
        vm.warp(block.timestamp + 16 days);
        uint256 before = sato.balanceOf(user);
        vm.prank(user);
        vault.redeem(1);
        assertGt(sato.balanceOf(user), before);
        (, uint256 locked,,,,,,, bool redeemed) = vault.vaults(1);
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

        (uint256 peakSato,,,,,,,,) = vault.vaults(1);

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

    function test_EarlyExitPenaltyCeilsPartialDay() public {
        vm.prank(user);
        vault.mint(1000 ether, SatoStonesVault.LockDays.Fifteen);

        (uint256 peakSato,, uint64 lockEnd,,,,,,) = vault.vaults(1);
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

    function test_SeasonUnclaimedGoesToCarry() public {
        vm.prank(user);
        vault.mint(100 ether, SatoStonesVault.LockDays.Fifteen);

        vm.warp(block.timestamp + 16 days);
        vault.finalizeSeason(0);

        uint256 carry = vault.undistributedCarry();
        assertGt(carry, 0);
    }
}
