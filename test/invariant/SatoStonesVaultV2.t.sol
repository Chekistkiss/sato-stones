// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {SatoStonesVaultV2} from "../../src/SatoStonesVaultV2.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockVRFCoordinator} from "../../src/mocks/MockVRFCoordinator.sol";
import {SatoStonesVaultV2Handler} from "./SatoStonesVaultV2Handler.sol";

/// @dev Invariant suite for spec v2.0 §12 (solvency + accounting).
contract SatoStonesVaultV2InvariantTest is StdInvariant, Test {
    SatoStonesVaultV2 public vault;
    MockERC20 public sato;
    SatoStonesVaultV2Handler public handler;

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
        handler = new SatoStonesVaultV2Handler(vault, sato);

        targetContract(address(handler));
        excludeContract(address(vault));
        excludeContract(address(sato));
    }

    function invariant_solvency() public view {
        assertGe(sato.balanceOf(address(vault)), vault.accountingLiabilities());
    }

    function invariant_sumLockedMatchesActiveVaults() public view {
        uint256 computed;
        uint256 n = vault.totalMintedEver();
        for (uint256 id = 1; id <= n; id++) {
            if (!_exists(id)) continue;
            (, uint256 locked,,,,,,,,) = vault.vaults(id);
            computed += locked;
        }
        assertEq(vault.sumLocked(), computed);
    }

    function invariant_noOverMintedSupply() public view {
        assertLe(vault.totalMintedEver(), vault.MAX_SUPPLY());
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        try vault.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
}
