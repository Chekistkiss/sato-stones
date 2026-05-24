// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721A} from "erc721a/ERC721A.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVRFCoordinatorV2Plus, VRFV2PlusClient} from "./interfaces/IVRFCoordinatorV2Plus.sol";
import {IERC2981} from "./interfaces/IERC2981.sol";
import {VRFConsumerBaseV2Plus} from "./base/VRFConsumerBaseV2Plus.sol";
import {
    GenesisCandidate,
    GenesisCheckpoint,
    LockDays,
    RarityTier,
    SeasonFinalizeState,
    Vault
} from "./VaultTypes.sol";
import {VaultGenesisLib} from "./libraries/VaultGenesisLib.sol";
import {VaultLotteryLib} from "./libraries/VaultLotteryLib.sol";
import {VaultSeasonLib} from "./libraries/VaultSeasonLib.sol";

/// @title SatoStonesVaultV2
/// @notice Loyalty vault NFT v2.0 — spec: _specs/sato-stones-vault-nft-v2.md
contract SatoStonesVaultV2 is ERC721A, ReentrancyGuard, VRFConsumerBaseV2Plus, IERC2981 {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_SUPPLY = 2100;
    uint256 public constant BPS = 10_000;
    uint256 public constant MINT_FEE_BPS = 400;
    uint256 public constant MINT_FEE_POOL_BPS = 5000;
    uint256 public constant MINT_FEE_DEV_BPS = 3500;
    uint256 public constant MINT_FEE_PRIZE_BPS = 1000;
    uint256 public constant MINT_FEE_BURN_BPS = 500;
    uint256 public constant PENALTY_POOL_BPS = 6500;
    uint256 public constant PENALTY_BURN_BPS = 500;
    uint256 public constant PENALTY_PRIZE_BPS = 2000;
    uint256 public constant PENALTY_DEV_BPS = 1000;
    uint256 public constant PENALTY_FLOOR_BPS = 500;
    uint256 public constant WALLET_CAP_BPS = 800;
    uint256 public constant LOTTERY_WALLET_CAP_BPS = 1500;
    uint256 public constant PRIZE_FIRST_BPS = 5000;
    uint256 public constant PRIZE_SECOND_BPS = 3000;
    uint256 public constant PRIZE_THIRD_BPS = 2000;
    uint256 public constant ROYALTY_BPS = 500;
    uint256 public constant ROYALTY_POOL_BPS = 4000;
    uint256 public constant ROYALTY_DEV_BPS = 4000;
    uint256 public constant ROYALTY_GENESIS_BPS = 2000;
    uint256 public constant SPONSOR_POOL_BPS = 9000;
    uint256 public constant SPONSOR_DEV_BPS = 1000;
    uint256 public constant MIN_GROSS = 50 ether;
    uint256 public constant MAX_GROSS_CAP = 50_000 ether;
    uint256 public constant MAX_GROSS_BPS_OF_SUPPLY = 50;
    uint256 public constant MIN_SATO_SUPPLY_AT_DEPLOY = 1_000_000 ether;
    uint256 public constant MAX_MINTS_PER_WALLET = 5;
    uint256 public constant MAX_GENESIS = 21;
    uint256 public constant SEASON_DURATION = 30 days;
    uint256 public constant TRANSFER_LOCKOUT = 24 hours;
    uint256 public constant FINALIZE_GRACE_PERIOD = 14 days;
    uint256 public constant PRIZE_DRAW_TIMEOUT = 1 days;
    uint256 public constant GENESIS_RACE_DURATION = 30 days;
    uint256 public constant GENESIS_MIN_SCORE = 4500 ether;
    uint256 public constant GENESIS_PEAK_FLOOR = 200 ether;
    uint256 public constant WEIGHT_SCALE = 1e9;
    uint256 public constant GENESIS_MULTIPLIER_BPS = 15_000;
    uint256 public constant MIN_PRIZE_DRAW_INTERVAL = 7 days;
    uint256 public constant MAX_PRIZE_DRAW_INTERVAL = 90 days;

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    IERC20 public immutable sato;
    address public immutable devAddress;
    uint256 public immutable t0;
    uint256 public immutable prizeMinSato;
    uint256 public immutable prizeDrawInterval;
    IVRFCoordinatorV2Plus public immutable vrfCoordinator;
    bytes32 public immutable vrfKeyHash;
    uint256 public immutable vrfSubscriptionId;
    uint16 public immutable vrfRequestConfirmations;
    uint32 public immutable vrfCallbackGasLimit;

    uint256 public totalMintedEver;
    uint256 public genesisMintedCount;
    uint256 public undistributedCarry;
    uint256 public devBalance;
    uint256 public prizeFund;
    uint256 public pendingDrawPrize;
    uint256 public pendingDrawRequestId;
    uint256 public pendingDrawTotalWeight;
    uint256 public lastPrizeDrawAt;
    uint256 public sumLocked;
    uint256 public sumUnclaimedSeasonClaims;
    uint256 public totalPendingPrize;
    uint256 public genesisRoyaltyPool;

    bool public genesisFinalized;
    uint64 public genesisFinalizedAt;
    uint256 public genesisCandidatesCount;

    mapping(uint256 => Vault) public vaults;
    mapping(uint256 => address) public originalMinter;
    mapping(address => uint256) public walletMintCount;
    mapping(uint256 => uint256) public seasonPool;
    mapping(uint256 => bool) public seasonFinalized;
    mapping(uint256 => bool) public seasonClosed;
    mapping(uint256 => uint256) public seasonTotalEffectiveWeight;
    mapping(uint256 => mapping(uint256 => address)) public seasonEndOwner;
    mapping(uint256 => mapping(uint256 => address)) public snapshotOwner;
    mapping(uint256 => mapping(uint256 => uint256)) public claimAmount;
    mapping(uint256 => mapping(uint256 => bool)) public seasonClaimed;
    mapping(uint256 => mapping(uint256 => uint256)) public weightInSeason;
    mapping(uint256 => SeasonFinalizeState) public seasonFinalize;
    mapping(uint256 => uint256) private _vrfRequestToDrawId;
    mapping(address => uint256) public pendingPrize;
    mapping(uint256 => mapping(uint256 => bool)) public genesisCheckpointClaimed;
    mapping(uint256 => mapping(uint256 => bool)) public genesisCheckpointEligible;

    GenesisCandidate[21] public genesisCandidates;
    GenesisCheckpoint[] public genesisCheckpoints;
    address[] private _drawMinters;
    uint256[] private _drawMinterWeights;

    string private _baseTokenURI;

    event StoneMinted(
        address indexed minter,
        uint256 indexed tokenId,
        uint256 grossSato,
        uint256 peakSato,
        LockDays lockDays,
        uint32 weightAtMint,
        uint64 mintTime,
        uint64 lockEnd
    );
    event GenesisCandidateUpdated(uint256 indexed tokenId, uint256 score, uint256 rank);
    event GenesisAssigned(uint256 indexed tokenId, uint8 rank, address indexed owner);
    event EarlyExit(
        uint256 indexed tokenId, address indexed owner, uint256 penaltySato, uint256 returnedSato
    );
    event Redeemed(uint256 indexed tokenId, address indexed owner, uint256 satoReturned);
    event Repledged(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 grossAmount,
        LockDays lockDays,
        uint256 peakSato,
        uint32 weightAtMint
    );
    event SeasonFinalized(uint256 indexed seasonId, uint256 distributable, uint256 totalEffectiveWeight);
    event SeasonClaimed(
        uint256 indexed seasonId, uint256 indexed tokenId, address indexed claimant, uint256 amount
    );
    event SeasonClosed(uint256 indexed seasonId, uint256 carried);
    event SeasonSponsored(
        uint256 indexed seasonId,
        address indexed sponsor,
        uint256 gross,
        uint256 netToPool,
        string memo
    );
    event PrizeFunded(uint256 amount, bytes32 indexed source);
    event PrizeRequested(uint256 indexed drawId, uint256 requestId, uint256 amount);
    event PrizeAssigned(
        uint256 indexed drawId, address indexed winner, uint8 place, uint256 amount
    );
    event PrizeDrawRecovered(uint256 indexed requestId, uint256 amount);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event DevWithdrawn(address indexed to, uint256 amount);
    event RoyaltyDistributed(
        uint256 royaltyIn,
        uint256 poolAmount,
        uint256 devAmount,
        uint256 genesisAmount,
        uint256 checkpointIdx
    );
    event GenesisRoyaltyClaimed(
        uint256 indexed tokenId, address indexed holder, uint256 amount, uint256 checkpointIdx
    );

    error MintedOut();
    error ExceedsWalletMintLimit();
    error InvalidLockDays();
    error DepositTooLow();
    error DepositTooHigh();
    error InsufficientReceived();
    error NotTokenOwner();
    error LockEndedUseRedeem();
    error LockNotEnded();
    error AlreadyRedeemed();
    error VaultEmpty();
    error SeasonNotEnded();
    error SeasonAlreadyFinalized();
    error SeasonNotFinalized();
    error NothingToClaim();
    error AlreadyClaimed();
    error NotSnapshotOwner();
    error SeasonTransferLocked();
    error NoDevBalance();
    error PrizePoolTooLow();
    error PrizeDrawTooSoon();
    error NoPendingPrize();
    error InvalidDrawRequest();
    error DrawPending();
    error NoEligibleTickets();
    error PrizeDrawNotTimedOut();
    error ZeroAddress();
    error GenesisCannotExit();
    error GenesisAlreadyFinalized();
    error GenesisRaceNotEnded();
    error FinalizeWindowExpired();
    error LotteryDisabled();
    error NoRoyaltyToDistribute();
    error NotGenesis();
    error NotDormant();
    error ZeroAmount();
    error InvalidSeason();
    error NotActiveAtCheckpoint();
    error CheckpointAlreadyClaimed();
    error SeasonFinalizeNotStarted();
    error SeasonFinalizeIncomplete();
    error SeasonAlreadyClosed();
    error InsufficientSatoSupplyAtDeploy();
    error InvalidPrizeDrawInterval();

    constructor(
        address satoToken,
        address devAddress_,
        uint256 prizeMinSato_,
        uint256 prizeDrawInterval_,
        address vrfCoordinator_,
        bytes32 vrfKeyHash_,
        uint256 vrfSubscriptionId_,
        uint16 vrfRequestConfirmations_,
        uint32 vrfCallbackGasLimit_,
        string memory baseURI_
    ) ERC721A("Sato Stones Vault", "VSTONE") VRFConsumerBaseV2Plus(vrfCoordinator_) {
        if (satoToken == address(0) || devAddress_ == address(0)) revert ZeroAddress();
        if (prizeMinSato_ == 0) revert ZeroAmount();
        if (
            prizeDrawInterval_ < MIN_PRIZE_DRAW_INTERVAL || prizeDrawInterval_ > MAX_PRIZE_DRAW_INTERVAL
        ) {
            revert InvalidPrizeDrawInterval();
        }
        sato = IERC20(satoToken);
        if (sato.totalSupply() < MIN_SATO_SUPPLY_AT_DEPLOY) revert InsufficientSatoSupplyAtDeploy();

        devAddress = devAddress_;
        prizeMinSato = prizeMinSato_;
        prizeDrawInterval = prizeDrawInterval_;
        vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator_);
        vrfKeyHash = vrfKeyHash_;
        vrfSubscriptionId = vrfSubscriptionId_;
        vrfRequestConfirmations = vrfRequestConfirmations_;
        vrfCallbackGasLimit = vrfCallbackGasLimit_;
        t0 = block.timestamp;
        lastPrizeDrawAt = block.timestamp;
        _baseTokenURI = baseURI_;
    }

    // -------------------------------------------------------------------------
    // Mint / repledge
    // -------------------------------------------------------------------------

    function mint(uint256 grossAmount, LockDays lockDays) external nonReentrant returns (uint256 tokenId) {
        if (totalMintedEver >= MAX_SUPPLY) revert MintedOut();
        if (walletMintCount[msg.sender] >= MAX_MINTS_PER_WALLET) revert ExceedsWalletMintLimit();
        tokenId = _mintVault(msg.sender, grossAmount, lockDays, true);
    }

    function repledge(uint256 tokenId, uint256 grossAmount, LockDays lockDays) external nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        Vault storage v = vaults[tokenId];
        if (!v.isGenesis) revert NotGenesis();
        if (v.satoLocked != 0 || !v.redeemed) revert NotDormant();
        _depositAndLock(tokenId, msg.sender, grossAmount, lockDays, false);
        v.redeemed = false;
        emit Repledged(
            tokenId, msg.sender, grossAmount, lockDays, v.peakSato, v.weightAtMint
        );
    }

    function _mintVault(address to, uint256 grossAmount, LockDays lockDays, bool countMint)
        internal
        returns (uint256 tokenId)
    {
        if (grossAmount < MIN_GROSS) revert DepositTooLow();
        if (grossAmount > _maxGrossForMint()) revert DepositTooHigh();

        uint256 received = _pullSato(to, grossAmount);
        (uint256 peakSato, uint256 mintFee) = _applyMintFee(received);

        tokenId = _nextTokenId();
        _mint(to, 1);
        originalMinter[tokenId] = to;

        _initVault(tokenId, peakSato, lockDays, false, 0);

        if (countMint) {
            walletMintCount[to]++;
            totalMintedEver++;
            emit StoneMinted(
                to,
                tokenId,
                grossAmount,
                peakSato,
                lockDays,
                vaults[tokenId].weightAtMint,
                vaults[tokenId].mintTime,
                vaults[tokenId].lockEnd
            );
            _maybeOfferGenesisCandidate(tokenId, peakSato, lockDays);
        }

        sumLocked += peakSato;
        _finalizeGenesisIfDue();
    }

    function _depositAndLock(
        uint256 tokenId,
        address payer,
        uint256 grossAmount,
        LockDays lockDays,
        bool countMint
    ) internal {
        if (grossAmount < MIN_GROSS) revert DepositTooLow();
        if (grossAmount > _maxGrossForMint()) revert DepositTooHigh();

        uint256 received = _pullSato(payer, grossAmount);
        (uint256 peakSato,) = _applyMintFee(received);

        Vault storage v = vaults[tokenId];
        v.peakSato = peakSato;
        v.satoLocked = peakSato;
        v.mintTime = uint64(block.timestamp);
        v.lockEnd = uint64(block.timestamp + _lockSeconds(lockDays));
        v.lockDays = lockDays;
        v.weightAtMint = _computeWeight(peakSato, lockDays, v.isGenesis);
        v.rarity = _rarityFromWeight(v.weightAtMint);
        sumLocked += peakSato;
        if (countMint) {
            _maybeOfferGenesisCandidate(tokenId, peakSato, lockDays);
        }
    }

    function _pullSato(address from, uint256 grossAmount) internal returns (uint256 received) {
        uint256 balanceBefore = sato.balanceOf(address(this));
        sato.safeTransferFrom(from, address(this), grossAmount);
        received = sato.balanceOf(address(this)) - balanceBefore;
        if (received < (grossAmount * (BPS - MINT_FEE_BPS)) / BPS) revert InsufficientReceived();
    }

    function _applyMintFee(uint256 received)
        internal
        returns (uint256 peakSato, uint256 mintFee)
    {
        mintFee = (received * MINT_FEE_BPS) / BPS;
        uint256 toPool = (mintFee * MINT_FEE_POOL_BPS) / BPS;
        uint256 toDev = (mintFee * MINT_FEE_DEV_BPS) / BPS;
        uint256 toPrize = (mintFee * MINT_FEE_PRIZE_BPS) / BPS;
        uint256 toBurn = (mintFee * MINT_FEE_BURN_BPS) / BPS;
        uint256 dust = mintFee - toPool - toDev - toPrize - toBurn;

        uint256 seasonId = _currentSeasonId();
        seasonPool[seasonId] += toPool + dust;
        devBalance += toDev;
        prizeFund += toPrize;
        if (toBurn > 0) sato.safeTransfer(DEAD, toBurn);

        emit PrizeFunded(toPrize, keccak256("mint"));
        peakSato = received - mintFee;
    }

    function _initVault(
        uint256 tokenId,
        uint256 peakSato,
        LockDays lockDays,
        bool isGenesis,
        uint8 genesisRank
    ) internal {
        vaults[tokenId] = Vault({
            peakSato: peakSato,
            satoLocked: peakSato,
            mintTime: uint64(block.timestamp),
            lockEnd: uint64(block.timestamp + _lockSeconds(lockDays)),
            weightAtMint: _computeWeight(peakSato, lockDays, isGenesis),
            lockDays: lockDays,
            rarity: _rarityFromWeight(_computeWeight(peakSato, lockDays, isGenesis)),
            isGenesis: isGenesis,
            genesisRank: genesisRank,
            redeemed: false
        });
    }

    // -------------------------------------------------------------------------
    // Exit / redeem
    // -------------------------------------------------------------------------

    function earlyExit(uint256 tokenId) external nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        Vault storage v = vaults[tokenId];
        if (v.isGenesis) revert GenesisCannotExit();
        if (v.redeemed || v.satoLocked == 0) revert VaultEmpty();
        if (block.timestamp >= v.lockEnd) revert LockEndedUseRedeem();

        uint256 penalty = _penaltySato(v);
        uint256 returned = v.satoLocked - penalty;
        sumLocked -= v.satoLocked;
        v.satoLocked = 0;

        _splitPenalty(penalty, _currentSeasonId());
        sato.safeTransfer(msg.sender, returned);
        _burn(tokenId);
        emit EarlyExit(tokenId, msg.sender, penalty, returned);
    }

    function redeem(uint256 tokenId) external nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        Vault storage v = vaults[tokenId];
        if (v.redeemed || v.satoLocked == 0) revert VaultEmpty();
        if (block.timestamp < v.lockEnd) revert LockNotEnded();

        uint256 amount = v.satoLocked;
        sumLocked -= amount;
        v.satoLocked = 0;
        v.redeemed = true;
        sato.safeTransfer(msg.sender, amount);
        emit Redeemed(tokenId, msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // Genesis race
    // -------------------------------------------------------------------------

    function _maybeOfferGenesisCandidate(uint256 tokenId, uint256 peakSato, LockDays lockDays) internal {
        if (genesisFinalized || block.timestamp >= t0 + GENESIS_RACE_DURATION) return;
        if (peakSato < GENESIS_PEAK_FLOOR) return;

        uint256 score = (peakSato * _lockMultiplierBps(lockDays)) / BPS;
        if (score < GENESIS_MIN_SCORE) return;

        _offerGenesisCandidate(tokenId, score);
    }

    function _offerGenesisCandidate(uint256 tokenId, uint256 score) internal {
        uint256 count = genesisCandidatesCount;
        (uint256 newCount, uint256 rank) = VaultGenesisLib.offerGenesisCandidate(
            genesisCandidates, MAX_GENESIS, tokenId, score, count
        );
        if (rank == 0) return;
        genesisCandidatesCount = newCount;
        emit GenesisCandidateUpdated(tokenId, score, rank);
    }

    function finalizeGenesis() external {
        _finalizeGenesisIfDue();
        if (!genesisFinalized) revert GenesisRaceNotEnded();
    }

    function _finalizeGenesisIfDue() internal {
        if (genesisFinalized) return;
        if (block.timestamp < t0 + GENESIS_RACE_DURATION) return;

        uint256 count = genesisCandidatesCount;
        for (uint256 i; i < count; i++) {
            uint256 tokenId = genesisCandidates[i].tokenId;
            if (!_exists(tokenId)) continue;
            Vault storage v = vaults[tokenId];
            v.isGenesis = true;
            v.genesisRank = uint8(i + 1);
            v.weightAtMint = _computeWeight(v.peakSato, v.lockDays, true);
            v.rarity = _rarityFromWeight(v.weightAtMint);
            emit GenesisAssigned(tokenId, v.genesisRank, ownerOf(tokenId));
        }

        genesisMintedCount = count;
        genesisFinalized = true;
        genesisFinalizedAt = uint64(block.timestamp);
    }

    // -------------------------------------------------------------------------
    // Seasons
    // -------------------------------------------------------------------------

    function finalizeSeasonChunk(uint256 seasonId, uint256 startId, uint256 endId)
        external
        nonReentrant
    {
        _requireCanFinalize(seasonId);
        if (endId < startId || startId < _startTokenId()) revert InvalidSeason();

        SeasonFinalizeState storage st = seasonFinalize[seasonId];
        if (st.cursor == 0) {
            st.distributable = seasonPool[seasonId] + undistributedCarry;
            seasonPool[seasonId] = 0;
            undistributedCarry = 0;
            st.cursor = _startTokenId();
        }

        uint256 maxId = _startTokenId() + totalMintedEver;
        if (endId >= maxId) endId = maxId - 1;

        for (uint256 id = startId; id <= endId; id++) {
            _processSeasonToken(seasonId, id, st);
        }
        st.cursor = endId + 1;
    }

    function finalizeSeasonClose(uint256 seasonId) external nonReentrant {
        _requireCanFinalize(seasonId);
        SeasonFinalizeState storage st = seasonFinalize[seasonId];
        if (st.cursor == 0) revert SeasonFinalizeNotStarted();
        if (st.cursor < _startTokenId() + totalMintedEver) revert SeasonFinalizeIncomplete();
        _closeSeasonFinalize(seasonId, st);
    }

    function closeMissedSeason(uint256 seasonId) external nonReentrant {
        if (block.timestamp <= _seasonEnd(seasonId) + FINALIZE_GRACE_PERIOD) revert SeasonNotEnded();
        if (seasonFinalized[seasonId] || seasonClosed[seasonId]) revert SeasonAlreadyFinalized();

        uint256 amount = seasonPool[seasonId];
        seasonPool[seasonId] = 0;
        undistributedCarry += amount;
        seasonClosed[seasonId] = true;
        seasonFinalized[seasonId] = true;
        emit SeasonClosed(seasonId, amount);
    }

    function _requireCanFinalize(uint256 seasonId) internal view {
        if (block.timestamp < _seasonEnd(seasonId)) revert SeasonNotEnded();
        if (block.timestamp > _seasonEnd(seasonId) + FINALIZE_GRACE_PERIOD) {
            revert FinalizeWindowExpired();
        }
        if (seasonFinalized[seasonId] || seasonClosed[seasonId]) revert SeasonAlreadyFinalized();
    }

    function _processSeasonToken(uint256 seasonId, uint256 id, SeasonFinalizeState storage st)
        internal
    {
        if (!_exists(id)) return;
        Vault storage v = vaults[id];
        if (v.satoLocked == 0) return;

        uint256 eff = _effectiveWeightAtFinalize(id, seasonId);
        if (eff == 0) return;

        address snap = seasonEndOwner[seasonId][id];
        if (snap == address(0)) snap = ownerOf(id);

        snapshotOwner[seasonId][id] = snap;
        weightInSeason[seasonId][id] = eff;
        st.totalEffectiveWeight += eff;
    }

    function _closeSeasonFinalize(uint256 seasonId, SeasonFinalizeState storage st) internal {
        uint256 distributable = st.distributable;
        uint256 totalWeight = st.totalEffectiveWeight;

        if (totalWeight == 0) {
            undistributedCarry = distributable;
            seasonFinalized[seasonId] = true;
            delete seasonFinalize[seasonId];
            emit SeasonFinalized(seasonId, 0, 0);
            return;
        }

        seasonTotalEffectiveWeight[seasonId] = totalWeight;
        uint256 allocated = _applyMinterCapAndSetClaims(seasonId, distributable, totalWeight);
        if (allocated < distributable) {
            undistributedCarry += distributable - allocated;
        }
        sumUnclaimedSeasonClaims += allocated;

        seasonFinalized[seasonId] = true;
        delete seasonFinalize[seasonId];
        emit SeasonFinalized(seasonId, distributable, totalWeight);
    }

    function _applyMinterCapAndSetClaims(
        uint256 seasonId,
        uint256 distributable,
        uint256 totalWeight
    ) internal returns (uint256 totalAllocated) {
        return VaultSeasonLib.applyMinterCapAndSetClaims(
            weightInSeason,
            claimAmount,
            originalMinter,
            seasonId,
            distributable,
            totalWeight,
            totalMintedEver,
            _startTokenId(),
            WALLET_CAP_BPS
        );
    }

    function claimSeason(uint256 seasonId, uint256 tokenId) external nonReentrant {
        _claimSeasonOne(seasonId, tokenId);
    }

    function claimSeasonBatch(uint256 seasonId, uint256[] calldata tokenIds) external nonReentrant {
        for (uint256 i; i < tokenIds.length; i++) {
            _claimSeasonOne(seasonId, tokenIds[i]);
        }
    }

    function _claimSeasonOne(uint256 seasonId, uint256 tokenId) internal {
        if (!seasonFinalized[seasonId]) revert SeasonNotFinalized();
        if (snapshotOwner[seasonId][tokenId] != msg.sender) revert NotSnapshotOwner();
        if (seasonClaimed[seasonId][tokenId]) revert AlreadyClaimed();
        uint256 amount = claimAmount[seasonId][tokenId];
        if (amount == 0) revert NothingToClaim();

        seasonClaimed[seasonId][tokenId] = true;
        sumUnclaimedSeasonClaims -= amount;
        sato.safeTransfer(msg.sender, amount);
        emit SeasonClaimed(seasonId, tokenId, msg.sender, amount);
    }

    function sponsorSeason(uint256 seasonId, uint256 amount, string calldata memo)
        external
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (seasonId < _currentSeasonId()) revert InvalidSeason();
        if (seasonFinalized[seasonId]) revert SeasonAlreadyFinalized();

        uint256 balanceBefore = sato.balanceOf(address(this));
        sato.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = sato.balanceOf(address(this)) - balanceBefore;

        uint256 toDev = (received * SPONSOR_DEV_BPS) / BPS;
        uint256 toPool = received - toDev;
        devBalance += toDev;
        seasonPool[seasonId] += toPool;

        emit SeasonSponsored(seasonId, msg.sender, received, toPool, memo);
    }

    // -------------------------------------------------------------------------
    // Lottery
    // -------------------------------------------------------------------------

    function canRequestPrizeDraw() public view returns (bool) {
        return address(vrfCoordinator) != address(0) && pendingDrawPrize == 0
            && pendingDrawRequestId == 0 && prizeFund >= prizeMinSato
            && block.timestamp >= lastPrizeDrawAt + prizeDrawInterval;
    }

    function requestPrizeDraw() external nonReentrant returns (uint256 requestId) {
        if (pendingDrawPrize != 0 || pendingDrawRequestId != 0) revert DrawPending();
        if (address(vrfCoordinator) == address(0)) revert LotteryDisabled();
        if (prizeFund < prizeMinSato) revert PrizePoolTooLow();
        if (block.timestamp < lastPrizeDrawAt + prizeDrawInterval) revert PrizeDrawTooSoon();

        _snapshotDrawMinters();
        if (pendingDrawTotalWeight == 0) revert NoEligibleTickets();

        pendingDrawPrize = prizeFund;
        prizeFund = 0;
        lastPrizeDrawAt = block.timestamp;

        uint256 drawId = block.timestamp;
        requestId = vrfCoordinator.requestRandomWords(
            IVRFCoordinatorV2Plus.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: vrfRequestConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: 3,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );
        _vrfRequestToDrawId[requestId] = drawId;
        pendingDrawRequestId = requestId;
        emit PrizeRequested(drawId, requestId, pendingDrawPrize);
    }

    function recoverTimedOutPrizeDraw() external nonReentrant {
        uint256 requestId = pendingDrawRequestId;
        uint256 amount = pendingDrawPrize;
        if (requestId == 0 || amount == 0) revert NoPendingPrize();
        if (block.timestamp < lastPrizeDrawAt + PRIZE_DRAW_TIMEOUT) revert PrizeDrawNotTimedOut();

        pendingDrawRequestId = 0;
        pendingDrawPrize = 0;
        pendingDrawTotalWeight = 0;
        prizeFund += amount;
        delete _vrfRequestToDrawId[requestId];
        _clearDrawMinters();
        emit PrizeDrawRecovered(requestId, amount);
    }

    function _fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 drawId = _vrfRequestToDrawId[requestId];
        if (drawId == 0 || requestId != pendingDrawRequestId) revert InvalidDrawRequest();

        uint256 amount = pendingDrawPrize;
        pendingDrawPrize = 0;
        pendingDrawRequestId = 0;
        delete _vrfRequestToDrawId[requestId];

        if (pendingDrawTotalWeight == 0 || amount == 0 || _drawMinters.length == 0) {
            prizeFund += amount;
            _clearDrawMinters();
            pendingDrawTotalWeight = 0;
            return;
        }

        uint256 firstAmt = (amount * PRIZE_FIRST_BPS) / BPS;
        uint256 secondAmt = (amount * PRIZE_SECOND_BPS) / BPS;
        uint256 thirdAmt = amount - firstAmt - secondAmt;

        address w1 = _drawWinner(randomWords[0]);
        if (w1 != address(0)) {
            _creditPrize(w1, firstAmt);
            emit PrizeAssigned(drawId, w1, 1, firstAmt);
        } else {
            prizeFund += firstAmt;
        }

        address w2 = _drawWinner(randomWords.length > 1 ? randomWords[1] : randomWords[0]);
        if (w2 != address(0)) {
            _creditPrize(w2, secondAmt);
            emit PrizeAssigned(drawId, w2, 2, secondAmt);
        } else {
            prizeFund += secondAmt;
        }

        address w3 = _drawWinner(randomWords.length > 2 ? randomWords[2] : randomWords[0]);
        if (w3 != address(0)) {
            _creditPrize(w3, thirdAmt);
            emit PrizeAssigned(drawId, w3, 3, thirdAmt);
        } else {
            prizeFund += thirdAmt;
        }

        _clearDrawMinters();
        pendingDrawTotalWeight = 0;
    }

    function _drawWinner(uint256 randomWord) internal returns (address) {
        (address winner, uint256 removed) = VaultLotteryLib.drawWinner(
            _drawMinters, _drawMinterWeights, randomWord, pendingDrawTotalWeight
        );
        pendingDrawTotalWeight -= removed;
        return winner;
    }

    function _creditPrize(address winner, uint256 amt) internal {
        if (amt == 0) return;
        pendingPrize[winner] += amt;
        totalPendingPrize += amt;
    }

    function claimPrize() external nonReentrant {
        uint256 amount = pendingPrize[msg.sender];
        if (amount == 0) revert NoPendingPrize();
        pendingPrize[msg.sender] = 0;
        totalPendingPrize -= amount;
        sato.safeTransfer(msg.sender, amount);
        emit PrizeClaimed(msg.sender, amount);
    }

    function _snapshotDrawMinters() internal {
        _clearDrawMinters();
        pendingDrawTotalWeight = VaultLotteryLib.snapshotDrawMinters(
            vaults,
            originalMinter,
            _drawMinters,
            _drawMinterWeights,
            totalMintedEver,
            _startTokenId(),
            LOTTERY_WALLET_CAP_BPS
        );
    }

    function _clearDrawMinters() internal {
        delete _drawMinters;
        delete _drawMinterWeights;
    }

    // -------------------------------------------------------------------------
    // Royalty / dev
    // -------------------------------------------------------------------------

    function royaltyInfo(uint256, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        return (address(this), (salePrice * ROYALTY_BPS) / BPS);
    }

    function distributeRoyalty() external nonReentrant {
        uint256 royaltyIn = _surplusBalance();
        if (royaltyIn == 0) revert NoRoyaltyToDistribute();

        uint256 toPool = (royaltyIn * ROYALTY_POOL_BPS) / BPS;
        uint256 toDev = (royaltyIn * ROYALTY_DEV_BPS) / BPS;
        uint256 toGenesis = (royaltyIn * ROYALTY_GENESIS_BPS) / BPS;
        uint256 dust = royaltyIn - toPool - toDev - toGenesis;

        seasonPool[_currentSeasonId()] += toPool + dust;
        devBalance += toDev;
        genesisRoyaltyPool += toGenesis;

        uint256 checkpointIdx = genesisCheckpoints.length;
        uint16 activeCount = _activeGenesisCount();
        genesisCheckpoints.push(
            GenesisCheckpoint({
                amount: toGenesis,
                activeCount: activeCount,
                timestamp: uint64(block.timestamp)
            })
        );
        if (activeCount > 0 && toGenesis > 0) {
            _markGenesisCheckpointEligible(checkpointIdx, activeCount);
        }

        emit RoyaltyDistributed(royaltyIn, toPool + dust, toDev, toGenesis, checkpointIdx);
    }

    function claimGenesisRoyalty(uint256 tokenId, uint256[] calldata checkpointIndices)
        external
        nonReentrant
    {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        Vault storage v = vaults[tokenId];
        if (!v.isGenesis || v.satoLocked == 0) revert NotActiveAtCheckpoint();

        uint256 total;
        for (uint256 i; i < checkpointIndices.length; i++) {
            uint256 idx = checkpointIndices[i];
            if (idx >= genesisCheckpoints.length) revert InvalidSeason();
            if (genesisCheckpointClaimed[tokenId][idx]) revert CheckpointAlreadyClaimed();
            if (!genesisCheckpointEligible[tokenId][idx]) revert NotActiveAtCheckpoint();

            GenesisCheckpoint storage cp = genesisCheckpoints[idx];
            if (cp.activeCount == 0) continue;
            uint256 share = cp.amount / cp.activeCount;
            genesisCheckpointClaimed[tokenId][idx] = true;
            total += share;
        }
        if (total == 0) revert NothingToClaim();
        genesisRoyaltyPool -= total;
        sato.safeTransfer(msg.sender, total);
        emit GenesisRoyaltyClaimed(tokenId, msg.sender, total, checkpointIndices[0]);
    }

    function withdrawDev() external nonReentrant {
        uint256 amount = devBalance;
        if (amount == 0) revert NoDevBalance();
        devBalance = 0;
        sato.safeTransfer(devAddress, amount);
        emit DevWithdrawn(devAddress, amount);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    function isActive(uint256 tokenId) external view returns (bool) {
        Vault storage v = vaults[tokenId];
        return _exists(tokenId) && v.satoLocked > 0 && block.timestamp < v.lockEnd;
    }

    function currentSeasonId() external view returns (uint256) {
        return _currentSeasonId();
    }

    function seasonEnd(uint256 seasonId) external view returns (uint256) {
        return _seasonEnd(seasonId);
    }

    function maxGrossForMint() external view returns (uint256) {
        return _maxGrossForMint();
    }

    function getEarlyExitPenalty(uint256 tokenId) external view returns (uint256) {
        Vault storage v = vaults[tokenId];
        if (v.satoLocked == 0 || block.timestamp >= v.lockEnd || v.isGenesis) return 0;
        return _penaltySato(v);
    }

    function timeToTransferLockout() external view returns (uint256) {
        uint256 end = _seasonEnd(_currentSeasonId());
        if (block.timestamp >= end) return 0;
        uint256 lockStart = end - TRANSFER_LOCKOUT;
        if (block.timestamp >= lockStart) return 0;
        return lockStart - block.timestamp;
    }

    function previewMint(uint256 grossAmount, LockDays lockDays)
        external
        view
        returns (
            uint256 peakSato,
            uint32 weightWithoutGenesis,
            uint32 weightIfGenesis,
            RarityTier rarityWithoutGenesis,
            RarityTier rarityIfGenesis,
            uint256 estGenesisScore,
            bool genesisRaceOpen
        )
    {
        peakSato = (grossAmount * (BPS - MINT_FEE_BPS)) / BPS;
        weightWithoutGenesis = _computeWeight(peakSato, lockDays, false);
        weightIfGenesis = _computeWeight(peakSato, lockDays, true);
        rarityWithoutGenesis = _rarityFromWeight(weightWithoutGenesis);
        rarityIfGenesis = _rarityFromWeight(weightIfGenesis);
        estGenesisScore = (peakSato * _lockMultiplierBps(lockDays)) / BPS;
        genesisRaceOpen = !genesisFinalized && block.timestamp < t0 + GENESIS_RACE_DURATION;
    }

    function previewEffectiveWeight(uint256 tokenId, uint256 seasonId)
        external
        view
        returns (uint256)
    {
        return _effectiveWeightAtFinalize(tokenId, seasonId);
    }

    function genesisLeaderboard() external view returns (GenesisCandidate[21] memory board, uint256 count) {
        count = genesisCandidatesCount;
        board = genesisCandidates;
    }

    function accountingLiabilities() public view returns (uint256) {
        uint256 liabilities = sumLocked + undistributedCarry + devBalance + prizeFund + pendingDrawPrize
            + totalPendingPrize + sumUnclaimedSeasonClaims + genesisRoyaltyPool;
        liabilities += _sumSeasonPools();
        return liabilities;
    }

    function activeGenesisCount() external view returns (uint16) {
        return _activeGenesisCount();
    }


    function pendingGenesisRoyalty(uint256 tokenId, uint256[] calldata checkpointIndices)
        external
        view
        returns (uint256 total)
    {
        Vault storage v = vaults[tokenId];
        if (!v.isGenesis || v.satoLocked == 0) return 0;
        for (uint256 i; i < checkpointIndices.length; i++) {
            uint256 idx = checkpointIndices[i];
            if (idx >= genesisCheckpoints.length) continue;
            if (genesisCheckpointClaimed[tokenId][idx]) continue;
            if (!genesisCheckpointEligible[tokenId][idx]) continue;
            GenesisCheckpoint storage cp = genesisCheckpoints[idx];
            if (cp.activeCount == 0) continue;
            total += cp.amount / cp.activeCount;
        }
    }

    function drawSnapshotCount() external view returns (uint256) {
        return _drawMinters.length;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A)
        returns (bool)
    {
        return interfaceId == _INTERFACE_ID_ERC2981 || ERC721A.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Internals
    // -------------------------------------------------------------------------

    function _surplusBalance() internal view returns (uint256) {
        uint256 bal = sato.balanceOf(address(this));
        uint256 liabilities = accountingLiabilities();
        if (bal <= liabilities) return 0;
        return bal - liabilities;
    }

    function _sumSeasonPools() internal view returns (uint256 total) {
        uint256 last = _currentSeasonId();
        for (uint256 s; s <= last; s++) {
            if (!seasonFinalized[s] && !seasonClosed[s]) total += seasonPool[s];
        }
    }

    function _effectiveWeightAtFinalize(uint256 tokenId, uint256 seasonId)
        internal
        view
        returns (uint256)
    {
        Vault storage v = vaults[tokenId];
        if (v.satoLocked == 0) return 0;

        uint256 seasonStart = t0 + seasonId * SEASON_DURATION;
        uint256 seasonEnd_ = seasonStart + SEASON_DURATION;

        uint256 activeStart = v.mintTime > seasonStart ? v.mintTime : seasonStart;
        uint256 activeEnd = v.lockEnd < seasonEnd_ ? v.lockEnd : seasonEnd_;
        if (activeEnd <= activeStart) return 0;

        uint256 secondsActive = activeEnd - activeStart;
        return (uint256(v.weightAtMint) * secondsActive) / SEASON_DURATION;
    }

    function _penaltySato(Vault storage v) internal view returns (uint256) {
        uint256 lockSecs = _lockSeconds(v.lockDays);
        uint256 secondsRemaining = uint256(v.lockEnd) - block.timestamp;
        uint256 daysRemaining = (secondsRemaining + 1 days - 1) / 1 days;
        uint256 lockDays = lockSecs / 1 days;
        uint256 penaltyBps = (_basePenaltyBps(v.lockDays) * daysRemaining) / lockDays;
        if (penaltyBps < PENALTY_FLOOR_BPS) penaltyBps = PENALTY_FLOOR_BPS;
        return (v.peakSato * penaltyBps) / BPS;
    }

    function _splitPenalty(uint256 penalty, uint256 seasonId) internal {
        uint256 toPool = (penalty * PENALTY_POOL_BPS) / BPS;
        uint256 toBurn = (penalty * PENALTY_BURN_BPS) / BPS;
        uint256 toPrize = (penalty * PENALTY_PRIZE_BPS) / BPS;
        uint256 toDev = (penalty * PENALTY_DEV_BPS) / BPS;
        uint256 dust = penalty - toPool - toBurn - toPrize - toDev;

        seasonPool[seasonId] += toPool + dust;
        if (toBurn > 0) sato.safeTransfer(DEAD, toBurn);
        prizeFund += toPrize;
        devBalance += toDev;
        emit PrizeFunded(toPrize, keccak256("penalty"));
    }

    function _activeGenesisCount() internal view returns (uint16 count) {
        uint256 n = totalMintedEver;
        for (uint256 id = _startTokenId(); id < _startTokenId() + n; id++) {
            Vault storage v = vaults[id];
            if (v.isGenesis && v.satoLocked > 0) count++;
        }
    }

    function _markGenesisCheckpointEligible(uint256 checkpointIdx, uint16 activeCount) internal {
        VaultGenesisLib.markGenesisCheckpointEligible(
            vaults,
            genesisCheckpointEligible,
            checkpointIdx,
            activeCount,
            totalMintedEver,
            _startTokenId()
        );
    }

    function _currentSeasonId() internal view returns (uint256) {
        return (block.timestamp - t0) / SEASON_DURATION;
    }

    function _seasonEnd(uint256 seasonId) internal view returns (uint256) {
        return t0 + (seasonId + 1) * SEASON_DURATION;
    }

    function _maxGrossForMint() internal view returns (uint256) {
        uint256 supply = sato.totalSupply();
        uint256 pctCap = (supply * MAX_GROSS_BPS_OF_SUPPLY) / BPS;
        return pctCap < MAX_GROSS_CAP ? pctCap : MAX_GROSS_CAP;
    }

    function _lockSeconds(LockDays lockDays) internal pure returns (uint256) {
        if (lockDays == LockDays.Thirty) return 30 days;
        if (lockDays == LockDays.Ninety) return 90 days;
        if (lockDays == LockDays.OneEighty) return 180 days;
        if (lockDays == LockDays.ThreeSixtyFive) return 365 days;
        revert InvalidLockDays();
    }

    function _basePenaltyBps(LockDays lockDays) internal pure returns (uint256) {
        if (lockDays == LockDays.Thirty) return 3500;
        if (lockDays == LockDays.Ninety) return 2500;
        if (lockDays == LockDays.OneEighty) return 2000;
        if (lockDays == LockDays.ThreeSixtyFive) return 1500;
        revert InvalidLockDays();
    }

    function _lockMultiplierBps(LockDays lockDays) internal pure returns (uint256) {
        if (lockDays == LockDays.Thirty) return 10_000;
        if (lockDays == LockDays.Ninety) return 25_000;
        if (lockDays == LockDays.OneEighty) return 50_000;
        if (lockDays == LockDays.ThreeSixtyFive) return 100_000;
        revert InvalidLockDays();
    }

    function _computeWeight(uint256 peakSato, LockDays lockDays, bool isGenesis)
        internal
        pure
        returns (uint32)
    {
        return VaultGenesisLib.computeWeight(
            peakSato, lockDays, isGenesis, WEIGHT_SCALE, GENESIS_MULTIPLIER_BPS
        );
    }

    function _rarityFromWeight(uint32 weight) internal pure returns (RarityTier) {
        return VaultGenesisLib.rarityFromWeight(weight);
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal override {
        if (from == address(0) || to == address(0)) return;

        uint256 seasonId = _currentSeasonId();
        uint256 end = _seasonEnd(seasonId);
        if (block.timestamp >= end - TRANSFER_LOCKOUT && block.timestamp < end) {
            revert SeasonTransferLocked();
        }

        for (uint256 i; i < quantity; i++) {
            seasonEndOwner[seasonId][startTokenId + i] = to;
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
