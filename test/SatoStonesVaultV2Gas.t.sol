// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SatoStonesVaultV2} from "../src/SatoStonesVaultV2.sol";
import {LockDays} from "../src/VaultTypes.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockVRFCoordinator} from "../src/mocks/MockVRFCoordinator.sol";

/// @notice Gas benchmarks for season finalization (spec v2.0 §16).
/// @dev Single-tx finalize at 500+ stones exceeds mainnet block gas; use chunked path on-chain.
contract SatoStonesVaultV2GasTest is Test {
    SatoStonesVaultV2 public vault;
    MockERC20 public sato;

    uint256 internal constant CHUNK_GAS_TARGET = 12_000_000;
    uint256 internal constant CLOSE_GAS_TARGET = 25_000_000;

    function setUp() public {
        sato = new MockERC20();
        MockVRFCoordinator vrf = new MockVRFCoordinator();
        vault = new SatoStonesVaultV2(
            address(sato),
            address(0xD3),
            10 ether,
            30 days,
            address(vrf),
            bytes32(uint256(1)),
            1,
            3,
            750_000,
            "ipfs://"
        );
    }

    function test_Gas_FinalizeSeason_100Stones_ChunkedFull() public {
        _benchMint(100);
        vm.warp(31 days);
        uint256 gChunk = _measureGasChunk(0, 1, 100);
        uint256 gClose = _measureGasClose(0);
        emit log_named_uint("finalizeSeason_gas_100_chunk", gChunk);
        emit log_named_uint("finalizeSeason_gas_100_close", gClose);
        assertLt(gChunk + gClose, CLOSE_GAS_TARGET);
    }

    function test_Gas_FinalizeSeason_500Stones_ChunkedFull_LogsOnly() public {
        _benchMint(500);
        vm.warp(31 days);
        uint256 gChunk = _measureGasChunk(0, 1, 500);
        uint256 gClose = _measureGasClose(0);
        emit log_named_uint("finalizeSeason_gas_500_chunk", gChunk);
        emit log_named_uint("finalizeSeason_gas_500_close", gClose);
        assertGt(gChunk, CHUNK_GAS_TARGET);
    }

    function test_Gas_FinalizeSeasonChunked_500Stones() public {
        _benchMint(500);
        vm.warp(31 days);

        uint256 g1 = _measureGasChunk(0, 1, 125);
        uint256 g2 = _measureGasChunk(0, 126, 250);
        uint256 g3 = _measureGasChunk(0, 251, 375);
        uint256 g4 = _measureGasChunk(0, 376, 500);
        uint256 g5 = _measureGasClose(0);

        emit log_named_uint("finalize_chunk_1_125", g1);
        emit log_named_uint("finalize_chunk_126_250", g2);
        emit log_named_uint("finalize_chunk_251_375", g3);
        emit log_named_uint("finalize_chunk_376_500", g4);
        emit log_named_uint("finalize_close", g5);

        assertLt(g1, CHUNK_GAS_TARGET);
        assertLt(g2, CHUNK_GAS_TARGET);
        assertLt(g3, CHUNK_GAS_TARGET);
        assertLt(g4, CHUNK_GAS_TARGET);
        assertLt(g5, CLOSE_GAS_TARGET);
        assertTrue(vault.seasonFinalized(0));
    }

    function test_Gas_FinalizeSeason_2100Stones_FullBench() public {
        if (vm.envOr("FOUNDRY_BENCH_FULL", uint256(0)) == 0) {
            return;
        }
        _benchMint(2100);
        vm.warp(31 days);
        uint256 g1 = _measureGasChunk(0, 1, 700);
        uint256 g2 = _measureGasChunk(0, 701, 1400);
        uint256 g3 = _measureGasChunk(0, 1401, 2100);
        uint256 g4 = _measureGasClose(0);
        emit log_named_uint("finalize_chunk_1_700", g1);
        emit log_named_uint("finalize_chunk_701_1400", g2);
        emit log_named_uint("finalize_chunk_1401_2100", g3);
        emit log_named_uint("finalize_close_2100", g4);
        assertTrue(vault.seasonFinalized(0));
    }

    function _measureGasChunk(uint256 seasonId, uint256 startId, uint256 endId)
        internal
        returns (uint256 gasUsed)
    {
        uint256 before = gasleft();
        vault.finalizeSeasonChunk(seasonId, startId, endId);
        gasUsed = before - gasleft();
    }

    function _measureGasClose(uint256 seasonId) internal returns (uint256 gasUsed) {
        uint256 before = gasleft();
        vault.finalizeSeasonClose(seasonId);
        gasUsed = before - gasleft();
    }

    function _benchMint(uint256 total) internal {
        uint256 wallets = (total + 4) / 5;
        uint256 minted;
        for (uint256 w; w < wallets; w++) {
            address user = address(uint160(0xBEEF0000 + w));
            sato.mint(user, 20_000_000 ether);
            vm.startPrank(user);
            sato.approve(address(vault), type(uint256).max);
            uint256 batch = 5;
            if (minted + batch > total) batch = total - minted;
            for (uint256 j; j < batch; j++) {
                vault.mint(100 ether, LockDays.Thirty);
                minted++;
            }
            vm.stopPrank();
        }
        assertEq(vault.totalMintedEver(), total);
    }
}
