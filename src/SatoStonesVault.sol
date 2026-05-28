// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721A} from "erc721a/ERC721A.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVRFCoordinatorV2Plus, VRFV2PlusClient} from "./interfaces/IVRFCoordinatorV2Plus.sol";

/// @title SatoStonesVault
/// @notice ERC721A vault: lock SATO per stone, one community reward season, progressive early-exit penalties.
contract SatoStonesVault is ERC721A, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum LockDays {
        Fifteen,
        Thirty,
        Sixty
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
        uint64 lockEnd;
        uint32 weightAtMint;
        LockDays lockDays;
        RarityTier rarity;
        bool redeemed;
    }

    uint256 public constant MAX_SUPPLY = 2100;
    uint256 public constant SINGLE_SEASON_ID = 0;
    uint256 public constant BPS = 10_000;
    uint256 public constant MINT_FEE_BPS = 200;
    uint256 public constant POOL_PENALTY_BPS = 4800;
    uint256 public constant BURN_PENALTY_BPS = 3300;
    uint256 public constant PRIZE_PENALTY_BPS = 1500;
    uint256 public constant DEV_PENALTY_BPS = 200;
    uint256 public constant MIN_GROSS = 100 ether;
    uint256 public constant MAX_GROSS_CAP = 10_000 ether;
    uint256 public constant MAX_MINTS_PER_WALLET = 10;
    uint256 public constant SEASON_DURATION = 15 days;
    uint256 public constant TRANSFER_LOCKOUT = 1 hours;
    uint256 public constant PRIZE_DRAW_TIMEOUT = 1 days;
    uint256 public constant WEIGHT_SCALE = 1e9;
    uint256 public constant DEFAULT_SEASON_CHUNK_SIZE = 100;
    uint256 public constant DEFAULT_PRIZE_CHUNK_SIZE = 100;

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
    uint256 public devBalance;
    uint256 public prizeFund;
    uint256 public pendingDrawPrize;
    uint256 public pendingDrawRequestId;
    uint256 public pendingDrawTotalWeight;
    uint256 public lastPrizeDrawAt;
    uint256 public seasonDistributable;
    uint256 public seasonProcessedUntil;
    bool public seasonSnapshotStarted;
    uint256 public prizeSnapshotNextTokenId;
    bool public prizeSnapshotStarted;
    uint256 public prizeSnapshotAt;

    mapping(uint256 => Vault) public vaults;
    mapping(address => uint256) public walletMintCount;
    mapping(uint256 => uint256) public seasonPool;
    mapping(uint256 => uint256) public seasonTotalWeight;
    mapping(uint256 => bool) public seasonFinalized;
    mapping(uint256 => mapping(uint256 => address)) public snapshotOwner;
    mapping(uint256 => mapping(uint256 => bool)) public seasonClaimed;
    mapping(uint256 => uint256) private _vrfRequestToDrawId;
    mapping(address => uint256) public pendingPrize;
    uint256[] private _drawTicketIds;
    uint256[] private _drawTicketCumulativeWeights;
    address[] private _drawTicketOwners;
    string private _baseTokenURI;
    uint256 private _pendingDrawId;

    event StoneMinted(address indexed minter, uint256 indexed tokenId, uint256 grossSato, uint256 peakSato, LockDays lockDays, uint32 weightAtMint);
    event EarlyExit(uint256 indexed tokenId, address indexed owner, uint256 penaltySato, uint256 returnedSato);
    event Redeemed(uint256 indexed tokenId, address indexed owner, uint256 satoReturned);
    event SeasonSnapshotProgress(uint256 indexed seasonId, uint256 nextTokenId, uint256 endTokenId);
    event SeasonFinalized(uint256 indexed seasonId, uint256 distributable, uint256 totalWeight);
    event SeasonClaimed(uint256 indexed seasonId, uint256 indexed tokenId, address indexed claimant, uint256 amount);
    event DevWithdrawn(address indexed to, uint256 amount);
    event PrizeFunded(uint256 amount);
    event PrizeSnapshotStarted(uint256 indexed drawId, uint256 amount);
    event PrizeSnapshotProgress(uint256 indexed drawId, uint256 nextTokenId, uint256 endTokenId);
    event PrizeRequested(uint256 indexed drawId, uint256 requestId, uint256 amount);
    event PrizeAssigned(uint256 indexed drawId, uint256 winnerTokenId, address indexed winner, uint256 amount);
    event PrizeDrawRecovered(uint256 indexed requestId, uint256 amount);
    event PrizeClaimed(address indexed winner, uint256 amount);

    error MintedOut();
    error ExceedsWalletMintLimit();
    error InvalidLockDays();
    error DepositTooLow();
    error DepositTooHigh();
    error InsufficientReceived();
    error NotTokenOwner();
    error LockEndedUseRedeem();
    error LockNotEnded();
    error VaultEmpty();
    error SeasonNotEnded();
    error SeasonAlreadyFinalized();
    error SeasonNotFinalized();
    error NothingToClaim();
    error AlreadyClaimed();
    error NotSnapshotOwner();
    error SeasonTransferLocked();
    error InvalidSeason();
    error SeasonEnded();
    error NoDevBalance();
    error PrizePoolTooLow();
    error PrizeDrawTooSoon();
    error NoPendingPrize();
    error OnlyVRFCoordinator();
    error InvalidDrawRequest();
    error DrawPending();
    error NoEligibleTickets();
    error PrizeDrawNotTimedOut();
    error ZeroAddress();

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
    ) ERC721A("Sato Stones Vault", "VSTONE") {
        if (satoToken == address(0) || devAddress_ == address(0)) revert ZeroAddress();
        sato = IERC20(satoToken);
        devAddress = devAddress_;
        t0 = block.timestamp;
        prizeMinSato = prizeMinSato_;
        prizeDrawInterval = prizeDrawInterval_;
        vrfCoordinator = IVRFCoordinatorV2Plus(vrfCoordinator_);
        vrfKeyHash = vrfKeyHash_;
        vrfSubscriptionId = vrfSubscriptionId_;
        vrfRequestConfirmations = vrfRequestConfirmations_;
        vrfCallbackGasLimit = vrfCallbackGasLimit_;
        lastPrizeDrawAt = block.timestamp;
        _baseTokenURI = baseURI_;
    }

    function mint(uint256 grossAmount, LockDays lockDays) external nonReentrant returns (uint256 tokenId) {
        if (totalMintedEver >= MAX_SUPPLY) revert MintedOut();
        if (walletMintCount[msg.sender] >= MAX_MINTS_PER_WALLET) revert ExceedsWalletMintLimit();
        if (block.timestamp >= _seasonEnd()) revert SeasonEnded();
        if (grossAmount < MIN_GROSS) revert DepositTooLow();

        uint256 maxGross = _maxGrossForMint();
        if (grossAmount > maxGross) revert DepositTooHigh();

        uint256 balanceBefore = sato.balanceOf(address(this));
        sato.safeTransferFrom(msg.sender, address(this), grossAmount);
        uint256 received = sato.balanceOf(address(this)) - balanceBefore;
        if (received < (grossAmount * (BPS - MINT_FEE_BPS)) / BPS) revert InsufficientReceived();

        uint256 mintFee = (received * MINT_FEE_BPS) / BPS;
        uint256 peakSato = received - mintFee;
        seasonPool[SINGLE_SEASON_ID] += mintFee;

        uint32 weight = _computeWeight(peakSato, lockDays);
        uint64 lockEnd = uint64(block.timestamp + _lockSeconds(lockDays));
        RarityTier rarity = _rarityFromWeight(weight);

        tokenId = _nextTokenId();
        _mint(msg.sender, 1);

        vaults[tokenId] = Vault({
            peakSato: peakSato,
            satoLocked: peakSato,
            lockEnd: lockEnd,
            weightAtMint: weight,
            lockDays: lockDays,
            rarity: rarity,
            redeemed: false
        });

        walletMintCount[msg.sender]++;
        totalMintedEver++;

        emit StoneMinted(msg.sender, tokenId, grossAmount, peakSato, lockDays, weight);
    }

    function earlyExit(uint256 tokenId) external nonReentrant {
        _revertIfVaultActionsPaused();
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        Vault storage v = vaults[tokenId];
        if (v.redeemed || v.satoLocked == 0) revert VaultEmpty();
        if (block.timestamp >= v.lockEnd) revert LockEndedUseRedeem();

        uint256 penalty = _penaltySato(v);
        uint256 returned = v.satoLocked - penalty;
        _splitPenalty(penalty);

        v.satoLocked = 0;
        sato.safeTransfer(msg.sender, returned);
        _burn(tokenId);

        emit EarlyExit(tokenId, msg.sender, penalty, returned);
    }

    function redeem(uint256 tokenId) external nonReentrant {
        _revertIfVaultActionsPaused();
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        Vault storage v = vaults[tokenId];
        if (v.redeemed || v.satoLocked == 0) revert VaultEmpty();
        if (block.timestamp < v.lockEnd) revert LockNotEnded();

        uint256 amount = v.satoLocked;
        v.satoLocked = 0;
        v.redeemed = true;
        sato.safeTransfer(msg.sender, amount);

        emit Redeemed(tokenId, msg.sender, amount);
    }

    function finalizeSeason(uint256 seasonId) external nonReentrant {
        _processSeasonSnapshot(seasonId, DEFAULT_SEASON_CHUNK_SIZE);
    }

    function processSeasonSnapshot(uint256 seasonId, uint256 maxTokens) external nonReentrant returns (bool done) {
        done = _processSeasonSnapshot(seasonId, maxTokens);
    }

    function claimSeason(uint256 seasonId, uint256 tokenId) external nonReentrant {
        if (seasonId != SINGLE_SEASON_ID) revert InvalidSeason();
        if (!seasonFinalized[seasonId]) revert SeasonNotFinalized();
        if (snapshotOwner[seasonId][tokenId] != msg.sender) revert NotSnapshotOwner();
        if (seasonClaimed[seasonId][tokenId]) revert AlreadyClaimed();

        uint256 amount = claimableSeasonAmount(seasonId, tokenId);
        if (amount == 0) revert NothingToClaim();

        seasonClaimed[seasonId][tokenId] = true;
        sato.safeTransfer(msg.sender, amount);

        emit SeasonClaimed(seasonId, tokenId, msg.sender, amount);
    }

    function withdrawDev() external nonReentrant {
        uint256 amount = devBalance;
        if (amount == 0) revert NoDevBalance();
        devBalance = 0;
        sato.safeTransfer(devAddress, amount);
        emit DevWithdrawn(devAddress, amount);
    }

    function canRequestPrizeDraw() public view returns (bool) {
        return address(vrfCoordinator) != address(0) && pendingDrawPrize == 0 && pendingDrawRequestId == 0
            && !prizeSnapshotStarted && prizeFund >= prizeMinSato
            && block.timestamp >= lastPrizeDrawAt + prizeDrawInterval;
    }

    function requestPrizeDraw() external nonReentrant returns (uint256 requestId) {
        if (pendingDrawPrize != 0 || pendingDrawRequestId != 0 || prizeSnapshotStarted) revert DrawPending();
        if (!canRequestPrizeDraw()) {
            if (prizeFund < prizeMinSato) revert PrizePoolTooLow();
            revert PrizeDrawTooSoon();
        }

        pendingDrawPrize = prizeFund;
        prizeFund = 0;
        lastPrizeDrawAt = block.timestamp;
        pendingDrawTotalWeight = 0;
        _pendingDrawId = block.timestamp;
        prizeSnapshotAt = block.timestamp;
        prizeSnapshotStarted = true;
        prizeSnapshotNextTokenId = _startTokenId();
        _clearDrawTickets();

        emit PrizeSnapshotStarted(_pendingDrawId, pendingDrawPrize);
        requestId = _processPrizeDrawSnapshot(DEFAULT_PRIZE_CHUNK_SIZE);
    }

    function processPrizeDrawSnapshot(uint256 maxTokens) external nonReentrant returns (bool done, uint256 requestId) {
        if (!prizeSnapshotStarted) revert NoPendingPrize();
        requestId = _processPrizeDrawSnapshot(maxTokens);
        done = !prizeSnapshotStarted;
    }

    function recoverTimedOutPrizeDraw() external nonReentrant {
        uint256 amount = pendingDrawPrize;
        uint256 requestId = pendingDrawRequestId;
        if (amount == 0) revert NoPendingPrize();
        if (block.timestamp < lastPrizeDrawAt + PRIZE_DRAW_TIMEOUT) revert PrizeDrawNotTimedOut();

        pendingDrawRequestId = 0;
        pendingDrawPrize = 0;
        pendingDrawTotalWeight = 0;
        prizeSnapshotStarted = false;
        prizeSnapshotNextTokenId = 0;
        prizeSnapshotAt = 0;
        _pendingDrawId = 0;
        prizeFund += amount;
        if (requestId != 0) delete _vrfRequestToDrawId[requestId];
        _clearDrawTickets();

        emit PrizeDrawRecovered(requestId, amount);
    }

    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external nonReentrant {
        if (msg.sender != address(vrfCoordinator)) revert OnlyVRFCoordinator();
        _fulfillRandomWords(requestId, randomWords);
    }

    function claimPrize() external nonReentrant {
        uint256 amount = pendingPrize[msg.sender];
        if (amount == 0) revert NoPendingPrize();
        pendingPrize[msg.sender] = 0;
        sato.safeTransfer(msg.sender, amount);
        emit PrizeClaimed(msg.sender, amount);
    }

    function currentSeasonId() external pure returns (uint256) {
        return SINGLE_SEASON_ID;
    }

    function maxGrossForMint() external view returns (uint256) {
        return _maxGrossForMint();
    }

    function getEarlyExitPenalty(uint256 tokenId) external view returns (uint256) {
        Vault storage v = vaults[tokenId];
        if (v.satoLocked == 0 || block.timestamp >= v.lockEnd) return 0;
        return _penaltySato(v);
    }

    function previewMint(uint256 grossAmount, LockDays lockDays)
        external
        pure
        returns (uint256 peakSato, uint32 weight, RarityTier rarity)
    {
        peakSato = (grossAmount * (BPS - MINT_FEE_BPS)) / BPS;
        weight = _computeWeight(peakSato, lockDays);
        rarity = _rarityFromWeight(weight);
    }

    function claimableSeasonAmount(uint256 seasonId, uint256 tokenId) public view returns (uint256) {
        if (seasonId != SINGLE_SEASON_ID || !seasonFinalized[seasonId] || seasonClaimed[seasonId][tokenId]) return 0;
        if (snapshotOwner[seasonId][tokenId] == address(0)) return 0;
        uint256 totalWeight = seasonTotalWeight[seasonId];
        if (totalWeight == 0) return 0;
        return (seasonDistributable * vaults[tokenId].weightAtMint) / totalWeight;
    }

    function _processSeasonSnapshot(uint256 seasonId, uint256 maxTokens) internal returns (bool done) {
        if (seasonId != SINGLE_SEASON_ID) revert InvalidSeason();
        if (block.timestamp < _seasonEnd()) revert SeasonNotEnded();
        if (seasonFinalized[seasonId]) revert SeasonAlreadyFinalized();

        if (!seasonSnapshotStarted) {
            seasonSnapshotStarted = true;
            seasonDistributable = seasonPool[seasonId];
            seasonPool[seasonId] = 0;
            seasonProcessedUntil = _startTokenId();
        }

        uint256 endTokenId = _startTokenId() + totalMintedEver;
        uint256 next = seasonProcessedUntil;
        uint256 stop = next + (maxTokens == 0 ? DEFAULT_SEASON_CHUNK_SIZE : maxTokens);
        if (stop > endTokenId) stop = endTokenId;
        uint256 end = _seasonEnd();

        for (uint256 id = next; id < stop; id++) {
            if (!_exists(id)) continue;
            Vault storage v = vaults[id];
            if (v.satoLocked == 0 || uint256(v.lockEnd) < end) continue;
            snapshotOwner[seasonId][id] = ownerOf(id);
            seasonTotalWeight[seasonId] += v.weightAtMint;
        }

        seasonProcessedUntil = stop;
        emit SeasonSnapshotProgress(seasonId, stop, endTokenId);

        if (stop < endTokenId) return false;

        seasonSnapshotStarted = false;
        seasonFinalized[seasonId] = true;
        uint256 totalWeight = seasonTotalWeight[seasonId];
        if (totalWeight == 0 && seasonDistributable > 0) {
            uint256 amount = seasonDistributable;
            seasonDistributable = 0;
            prizeFund += amount;
            emit PrizeFunded(amount);
        }
        emit SeasonFinalized(seasonId, seasonDistributable, totalWeight);
        return true;
    }

    function _processPrizeDrawSnapshot(uint256 maxTokens) internal returns (uint256 requestId) {
        uint256 endTokenId = _startTokenId() + totalMintedEver;
        uint256 next = prizeSnapshotNextTokenId;
        uint256 stop = next + (maxTokens == 0 ? DEFAULT_PRIZE_CHUNK_SIZE : maxTokens);
        if (stop > endTokenId) stop = endTokenId;

        uint256 cumulative = pendingDrawTotalWeight;
        for (uint256 id = next; id < stop; id++) {
            if (!_exists(id)) continue;
            Vault storage v = vaults[id];
            if (v.satoLocked == 0 || uint256(v.lockEnd) <= prizeSnapshotAt) continue;

            cumulative += v.weightAtMint;
            _drawTicketIds.push(id);
            _drawTicketCumulativeWeights.push(cumulative);
            _drawTicketOwners.push(ownerOf(id));
        }
        pendingDrawTotalWeight = cumulative;
        prizeSnapshotNextTokenId = stop;
        emit PrizeSnapshotProgress(_pendingDrawId, stop, endTokenId);

        if (stop < endTokenId) return 0;

        prizeSnapshotStarted = false;
        prizeSnapshotNextTokenId = 0;
        prizeSnapshotAt = 0;
        if (pendingDrawTotalWeight == 0) {
            uint256 amount = pendingDrawPrize;
            pendingDrawPrize = 0;
            prizeFund += amount;
            _pendingDrawId = 0;
            prizeSnapshotAt = 0;
            _clearDrawTickets();
            emit PrizeDrawRecovered(0, amount);
            return 0;
        }

        uint256 drawId = _pendingDrawId;
        _pendingDrawId = 0;
        prizeSnapshotAt = 0;
        requestId = vrfCoordinator.requestRandomWords(
            IVRFCoordinatorV2Plus.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: vrfRequestConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );
        _vrfRequestToDrawId[requestId] = drawId;
        pendingDrawRequestId = requestId;
        emit PrizeRequested(drawId, requestId, pendingDrawPrize);
    }

    function _fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal {
        uint256 drawId = _vrfRequestToDrawId[requestId];
        if (drawId == 0 || requestId != pendingDrawRequestId || randomWords.length == 0) revert InvalidDrawRequest();

        uint256 amount = pendingDrawPrize;
        pendingDrawPrize = 0;

        if (pendingDrawTotalWeight == 0 || amount == 0) {
            prizeFund += amount;
            pendingDrawRequestId = 0;
            pendingDrawTotalWeight = 0;
            prizeSnapshotAt = 0;
            delete _vrfRequestToDrawId[requestId];
            _clearDrawTickets();
            return;
        }

        uint256 roll = randomWords[0] % pendingDrawTotalWeight;
        uint256 winnerIndex = _winnerTicketIndex(roll);
        uint256 winnerId = _drawTicketIds[winnerIndex];
        address winner = _drawTicketOwners[winnerIndex];
        pendingPrize[winner] += amount;

        emit PrizeAssigned(drawId, winnerId, winner, amount);
        pendingDrawRequestId = 0;
        pendingDrawTotalWeight = 0;
        prizeSnapshotAt = 0;
        delete _vrfRequestToDrawId[requestId];
        _clearDrawTickets();
    }

    function _splitPenalty(uint256 penalty) internal {
        uint256 toPool = (penalty * POOL_PENALTY_BPS) / BPS;
        uint256 toBurn = (penalty * BURN_PENALTY_BPS) / BPS;
        uint256 toPrize = (penalty * PRIZE_PENALTY_BPS) / BPS;
        uint256 toDev = (penalty * DEV_PENALTY_BPS) / BPS;
        uint256 dust = penalty - toPool - toBurn - toPrize - toDev;
        uint256 communityShare = toPool + dust;
        uint256 fundedPrize = toPrize;

        if (seasonFinalized[SINGLE_SEASON_ID]) {
            prizeFund += communityShare;
            fundedPrize += communityShare;
        } else {
            seasonPool[SINGLE_SEASON_ID] += communityShare;
        }
        sato.safeTransfer(DEAD, toBurn);
        prizeFund += toPrize;
        devBalance += toDev;

        emit PrizeFunded(fundedPrize);
    }

    function _winnerTicketIndex(uint256 roll) internal view returns (uint256) {
        uint256 lo;
        uint256 hi = _drawTicketCumulativeWeights.length;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            if (roll < _drawTicketCumulativeWeights[mid]) hi = mid;
            else lo = mid + 1;
        }
        return lo;
    }

    function _clearDrawTickets() internal {
        delete _drawTicketIds;
        delete _drawTicketCumulativeWeights;
        delete _drawTicketOwners;
    }

    function _revertIfVaultActionsPaused() internal view {
        if ((block.timestamp >= _seasonEnd() && !seasonFinalized[SINGLE_SEASON_ID]) || prizeSnapshotStarted) {
            revert SeasonTransferLocked();
        }
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _maxGrossForMint() internal view returns (uint256) {
        uint256 pctCap = (sato.totalSupply() * 10) / BPS;
        return pctCap < MAX_GROSS_CAP ? pctCap : MAX_GROSS_CAP;
    }

    function _lockSeconds(LockDays lockDays) internal pure returns (uint256) {
        if (lockDays == LockDays.Fifteen) return 15 days;
        if (lockDays == LockDays.Thirty) return 30 days;
        if (lockDays == LockDays.Sixty) return 60 days;
        revert InvalidLockDays();
    }

    function _basePenaltyBps(LockDays lockDays) internal pure returns (uint256) {
        if (lockDays == LockDays.Fifteen) return 3000;
        if (lockDays == LockDays.Thirty) return 2500;
        if (lockDays == LockDays.Sixty) return 2000;
        revert InvalidLockDays();
    }

    function _lockMultiplierBps(LockDays lockDays) internal pure returns (uint256) {
        if (lockDays == LockDays.Fifteen) return 10_000;
        if (lockDays == LockDays.Thirty) return 18_000;
        if (lockDays == LockDays.Sixty) return 30_000;
        revert InvalidLockDays();
    }

    function _computeWeight(uint256 peakSato, LockDays lockDays) internal pure returns (uint32) {
        uint256 w = (_sqrt(peakSato) * _lockMultiplierBps(lockDays)) / WEIGHT_SCALE;
        if (w > type(uint32).max) w = type(uint32).max;
        return uint32(w);
    }

    function _rarityFromWeight(uint32 weight) internal pure returns (RarityTier) {
        if (weight >= 150) return RarityTier.Mythic;
        if (weight >= 50) return RarityTier.Rare;
        if (weight >= 15) return RarityTier.Uncommon;
        return RarityTier.Common;
    }

    function _penaltySato(Vault storage v) internal view returns (uint256) {
        uint256 secondsRemaining = uint256(v.lockEnd) - block.timestamp;
        uint256 daysRemaining = (secondsRemaining + 1 days - 1) / 1 days;
        uint256 lockDays = _lockSeconds(v.lockDays) / 1 days;
        uint256 penaltyBps = (_basePenaltyBps(v.lockDays) * daysRemaining) / lockDays;
        return (v.peakSato * penaltyBps) / BPS;
    }

    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function _seasonEnd() internal view returns (uint256) {
        return t0 + SEASON_DURATION;
    }

    function _beforeTokenTransfers(address from, address to, uint256, uint256) internal view override {
        if (from != address(0) && to != address(0)) {
            uint256 end = _seasonEnd();
            if ((!seasonFinalized[SINGLE_SEASON_ID] && block.timestamp >= end - TRANSFER_LOCKOUT) || prizeSnapshotStarted) {
                revert SeasonTransferLocked();
            }
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
