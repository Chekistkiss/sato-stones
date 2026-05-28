// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SatoStonesVault} from "../src/SatoStonesVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockVRFCoordinator} from "../src/mocks/MockVRFCoordinator.sol";

contract SatoStonesVaultChunkedTest is Test {
    SatoStonesVault public vault;
    MockERC20 public sato;
    MockVRFCoordinator public vrf;

    function setUp() public {
        sato = new MockERC20();
        vrf = new MockVRFCoordinator();
        vault = new SatoStonesVault(
            address(sato),
            address(0xD3),
            1 ether,
            30 days,
            address(vrf),
            bytes32(uint256(1)),
            1,
            3,
            250_000,
            "ipfs://"
        );
    }

    function _wallet(uint256 i) internal pure returns (address) {
        return address(uint160(10_000 + (i / 10)));
    }

    function _mintMany(uint256 n, SatoStonesVault.LockDays lockDays) internal {
        for (uint256 i; i < n; i++) {
            address w = _wallet(i);
            sato.mint(w, 1_000_000 ether);
            vm.startPrank(w);
            sato.approve(address(vault), type(uint256).max);
            vault.mint(100 ether, lockDays);
            vm.stopPrank();
        }
    }

    function test_ChunkedSeasonFinalizesFullSupply() public {
        _mintMany(2100, SatoStonesVault.LockDays.Sixty);
        vm.warp(block.timestamp + vault.SEASON_DURATION());

        uint256 steps;
        while (!vault.seasonFinalized(0)) {
            uint256 gasBefore = gasleft();
            vault.processSeasonSnapshot(0, 150);
            uint256 used = gasBefore - gasleft();
            assertLt(used, 25_000_000);
            steps++;
            assertLe(steps, 20);
        }

        assertEq(vault.seasonProcessedUntil(), 2101);
        assertGt(vault.seasonTotalWeight(0), 0);
        assertGt(vault.claimableSeasonAmount(0, 1), 0);
    }

    function test_ChunkedPrizeSnapshotRequestsVrfForFullSupply() public {
        _mintMany(2100, SatoStonesVault.LockDays.Sixty);

        address first = _wallet(0);
        vm.prank(first);
        vault.earlyExit(1);

        vm.warp(block.timestamp + 31 days);
        uint256 gasBefore = gasleft();
        uint256 requestId = vault.requestPrizeDraw();
        uint256 used = gasBefore - gasleft();
        assertLt(used, 25_000_000);

        uint256 steps;
        while (vault.prizeSnapshotStarted()) {
            gasBefore = gasleft();
            (, requestId) = vault.processPrizeDrawSnapshot(150);
            used = gasBefore - gasleft();
            assertLt(used, 25_000_000);
            steps++;
            assertLe(steps, 20);
        }

        assertGt(requestId, 0);
        assertGt(vault.pendingDrawTotalWeight(), 0);
        assertGt(vault.pendingDrawPrize(), 0);
        assertGt(vault.pendingDrawRequestId(), 0);
    }
}
