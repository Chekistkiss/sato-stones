// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721A} from "erc721a/ERC721A.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVRFCoordinatorV2Plus, VRFV2PlusClient} from "./interfaces/IVRFCoordinatorV2Plus.sol";

/// @title SatoStonesVault
/// @notice ERC721A vault: lock SATO per stone, seasonal pool, progressive early-exit penalties.
/// @dev Spec: _specs/sato-stones-vault-nft.md v1.3
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
        bool isGenesis;
        uint8 genesisRank;
        bool redeemed;
    }

    uint256 public constant MAX_SUPPLY = 2100;
    uint256 public constant BPS = 10_000;
    uint256 public constant MINT_FEE_BPS = 200;
    uint256 public constant POOL_PENALTY_BPS = 4800;
    uint256 public constant BURN_PENALTY_BPS = 3300;
    uint256 public constant PRIZE_PENALTY_BPS = 1500;
    uint256 public constant DEV_PENALTY_BPS = 200;
    uint256 public constant MAX_CLAIM_BPS = 1000;
    uint256 public constant MIN_GROSS = 100 ether;
    uint256 public constant GENESIS_GROSS = 500 ether;
    uint256 public constant MAX_GROSS_CAP = 10_000 ether;
    uint256 public constant MAX_MINTS_PER_WALLET = 10;
    uint256 public constant MAX_GENESIS = 21;
    uint256 public constant SEASON_DURATION = 15 days;
    uint256 public constant TRANSFER_LOCKOUT = 1 hours;
    uint256 public constant PRIZE_DRAW_TIMEOUT = 1 days;
    uint256 public constant WEIGHT_SCALE = 1e9;
    uint256 public constant GENESIS_BPS = 12_000; // 1.2x

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

    uint256 public genesisMinted;
    uint256 public totalMintedEver;
    uint256 public undistributedCarry;
    uint256 public devBalance;
    uint256 public prizeFund;
    uint256 public pendingDrawPrize;
    uint256 public pendingDrawRequestId;
    uint256 public pendingDrawTotalWeight;
    uint256 public lastPrizeDrawAt;

    mapping(uint256 => Vault) public vaults;
    mapping(address => uint256) public walletMintCount;
    mapping(uint256 => uint256) public seasonPool;
    mapping(uint256 => uint256) public seasonTotalWeight;
    mapping(uint256 => bool) public seasonFinalized;
    mapping(uint256 => mapping(uint256 => address)) public snapshotOwner;
    mapping(uint256 => mapping(uint256 => uint256)) public claimAmount;
    mapping(uint256 => mapping(uint256 => bool)) public seasonClaimed;
    mapping(uint256 => uint256) private _vrfRequestToDrawId;
    mapping(address => uint256) public pendingPrize;
    uint256[] private _drawTicketIds;
    uint256[] private _drawTicketCumulativeWeights;
    address[] private _drawTicketOwners;

    event StoneMinted(
        address indexed minter,
        uint256 indexed tokenId,
        uint256 grossSato,
        uint256 peakSato,
        LockDays lockDays,
        uint32 weightAtMint,
        bool isGenesis,
        uint8 genesisRank
    );
    event EarlyExit(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 penaltySato,
        uint256 returnedSato
    );
    event Redeemed(uint256 indexed tokenId, address indexed owner, uint256 satoReturned);
    event SeasonFinalized(uint256 indexed seasonId, uint256 distributable, uint256 totalWeight);
    event SeasonClaimed(uint256 indexed seasonId, uint256 indexed tokenId, address indexed claimant, uint256 amount);
    event DevWithdrawn(address indexed to, uint256 amount);
    event PrizeFunded(uint256 amount);
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
    error OnlyVRFCoordinator();
    error InvalidDrawRequest();
    error DrawPending();
    error NoEligibleTickets();
    error PrizeDrawNotTimedOut();
    error TransferFailed();
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

    string private _baseTokenURI;

    // -------------------------------------------------------------------------
    // Mint
    // -------------------------------------------------------------------------

    function mint(uint256 grossAmount, LockDays lockDays) external nonReentrant returns (uint256 tokenId) {
        if (totalMintedEver >= MAX_SUPPLY) revert MintedOut();
        if (walletMintCount[msg.sender] >= MAX_MINTS_PER_WALLET) revert ExceedsWalletMintLimit();
        if (grossAmount < MIN_GROSS) revert DepositTooLow();

        uint256 maxGross = _maxGrossForMint();
        if (grossAmount > maxGross) revert DepositTooHigh();

        uint256 balanceBefore = sato.balanceOf(address(this));
        sato.safeTransferFrom(msg.sender, address(this), grossAmount);
        uint256 received = sato.balanceOf(address(this)) - balanceBefore;
        if (received < (grossAmount * (BPS - MINT_FEE_BPS)) / BPS) revert InsufficientReceived();

        uint256 seasonId = _currentSeasonId();
        uint256 mintFee = (received * MINT_FEE_BPS) / BPS;
        uint256 peakSato = received - mintFee;
        seasonPool[seasonId] += mintFee;

        bool isGenesis;
        uint8 genesisRank;
        if (received >= GENESIS_GROSS && genesisMinted < MAX_GENESIS) {
            isGenesis = true;
            genesisRank = uint8(genesisMinted + 1);
            genesisMinted++;
        }

        uint32 weight = _computeWeight(peakSato, lockDays, isGenesis);
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
            isGenesis: isGenesis,
            genesisRank: genesisRank,
            redeemed: false
        });

        walletMintCount[msg.sender]++;
        totalMintedEver++;

        emit StoneMinted(msg.sender, tokenId, grossAmount, peakSato, lockDays, weight, isGenesis, genesisRank);
    }

    function earlyExit(uint256 tokenId) external nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        Vault storage v = vaults[tokenId];
        if (v.redeemed || v.satoLocked == 0) revert VaultEmpty();
        if (block.timestamp >= v.lockEnd) revert LockEndedUseRedeem();

        uint256 penalty = _penaltySato(v);
        uint256 returned = v.satoLocked - penalty;
        _splitPenalty(penalty, _currentSeasonId());

        v.satoLocked = 0;
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
        v.satoLocked = 0;
        v.redeemed = true;
        sato.safeTransfer(msg.sender, amount);

        emit Redeemed(tokenId, msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // Seasons
    // -------------------------------------------------------------------------

    function finalizeSeason(uint256 seasonId) external nonReentrant {
        if (block.timestamp < t0 + (seasonId + 1) * SEASON_DURATION) revert SeasonNotEnded();
        if (seasonFinalized[seasonId]) revert SeasonAlreadyFinalized();

        uint256 distributable = seasonPool[seasonId] + undistributedCarry;
        undistributedCarry = 0;
        seasonPool[seasonId] = 0;

        uint256 totalWeight;
        for (uint256 id = _startTokenId(); id < _startTokenId() + totalMintedEver; id++) {
            if (!_exists(id)) continue;
            Vault storage v = vaults[id];
            if (v.satoLocked == 0 || block.timestamp >= v.lockEnd) continue;

            snapshotOwner[seasonId][id] = ownerOf(id);
            totalWeight += v.weightAtMint;
        }

        if (totalWeight == 0) {
            undistributedCarry = distributable;
            seasonFinalized[seasonId] = true;
            emit SeasonFinalized(seasonId, 0, 0);
            return;
        }

        seasonTotalWeight[seasonId] = totalWeight;

        uint256 allocated = _applyWalletCapAndSetClaims(seasonId, distributable, totalWeight);
        if (allocated < distributable) {
            undistributedCarry += distributable - allocated;
        }

        seasonFinalized[seasonId] = true;
        emit SeasonFinalized(seasonId, distributable, totalWeight);
    }

    function claimSeason(uint256 seasonId, uint256 tokenId) external nonReentrant {
        if (!seasonFinalized[seasonId]) revert SeasonNotFinalized();
        if (snapshotOwner[seasonId][tokenId] != msg.sender) revert NotSnapshotOwner();
        if (seasonClaimed[seasonId][tokenId]) revert AlreadyClaimed();

        uint256 amount = claimAmount[seasonId][tokenId];
        if (amount == 0) revert NothingToClaim();

        seasonClaimed[seasonId][tokenId] = true;
        sato.safeTransfer(msg.sender, amount);

        emit SeasonClaimed(seasonId, tokenId, msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // Dev & lottery
    // -------------------------------------------------------------------------

    function withdrawDev() external nonReentrant {
        uint256 amount = devBalance;
        if (amount == 0) revert NoDevBalance();
        devBalance = 0;
        sato.safeTransfer(devAddress, amount);
        emit DevWithdrawn(devAddress, amount);
    }

    function canRequestPrizeDraw() public view returns (bool) {
        return address(vrfCoordinator) != address(0) && pendingDrawPrize == 0 && pendingDrawRequestId == 0
            && prizeFund >= prizeMinSato && block.timestamp >= lastPrizeDrawAt + prizeDrawInterval;
    }

    function requestPrizeDraw() external nonReentrant returns (uint256 requestId) {
        if (pendingDrawPrize != 0) revert DrawPending();
        if (pendingDrawRequestId != 0) revert DrawPending();
        if (!canRequestPrizeDraw()) {
            if (prizeFund < prizeMinSato) revert PrizePoolTooLow();
            revert PrizeDrawTooSoon();
        }

        _snapshotDrawTickets();
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
                numWords: 1,
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
        _clearDrawTickets();

        emit PrizeDrawRecovered(requestId, amount);
    }

    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external nonReentrant {
        if (msg.sender != address(vrfCoordinator)) revert OnlyVRFCoordinator();
        _fulfillRandomWords(requestId, randomWords);
    }

    function _fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal {
        uint256 drawId = _vrfRequestToDrawId[requestId];
        if (drawId == 0 || requestId != pendingDrawRequestId) revert InvalidDrawRequest();

        uint256 amount = pendingDrawPrize;
        pendingDrawPrize = 0;

        if (pendingDrawTotalWeight == 0 || amount == 0) {
            prizeFund += amount;
            pendingDrawRequestId = 0;
            pendingDrawTotalWeight = 0;
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
        delete _vrfRequestToDrawId[requestId];
        _clearDrawTickets();
    }

    function claimPrize() external nonReentrant {
        uint256 amount = pendingPrize[msg.sender];
        if (amount == 0) revert NoPendingPrize();
        pendingPrize[msg.sender] = 0;
        sato.safeTransfer(msg.sender, amount);
        emit PrizeClaimed(msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    function currentSeasonId() external view returns (uint256) {
        return _currentSeasonId();
    }

    function maxGrossForMint() external view returns (uint256) {
        return _maxGrossForMint();
    }

    function getEarlyExitPenalty(uint256 tokenId) external view returns (uint256) {
        Vault storage v = vaults[tokenId];
        if (v.satoLocked == 0 || block.timestamp >= v.lockEnd) return 0;
        return _penaltySato(v);
    }

    function previewMint(uint256 grossAmount, LockDays lockDays, bool assumeGenesis)
        external
        view
        returns (
            uint256 peakSato,
            uint32 weight,
            RarityTier rarity,
            bool wouldBeGenesis
        )
    {
        // Matches mint when `received == grossAmount` (no fee-on-transfer on SATO)
        peakSato = (grossAmount * (BPS - MINT_FEE_BPS)) / BPS;
        wouldBeGenesis =
            grossAmount >= GENESIS_GROSS && genesisMinted < MAX_GENESIS && assumeGenesis;
        weight = _computeWeight(peakSato, lockDays, wouldBeGenesis);
        rarity = _rarityFromWeight(weight);
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _currentSeasonId() internal view returns (uint256) {
        return (block.timestamp - t0) / SEASON_DURATION;
    }

    function _maxGrossForMint() internal view returns (uint256) {
        uint256 supply = sato.totalSupply();
        uint256 pctCap = (supply * 10) / BPS;
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

    function _computeWeight(uint256 peakSato, LockDays lockDays, bool isGenesis)
        internal
        pure
        returns (uint32)
    {
        uint256 root = _sqrt(peakSato);
        uint256 w = (root * _lockMultiplierBps(lockDays)) / WEIGHT_SCALE;
        if (isGenesis) {
            w = (w * GENESIS_BPS) / BPS;
        }
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
        uint256 lockSecs = _lockSeconds(v.lockDays);
        uint256 secondsRemaining = uint256(v.lockEnd) - block.timestamp;
        uint256 daysRemaining = (secondsRemaining + 1 days - 1) / 1 days;
        uint256 lockDays = lockSecs / 1 days;
        uint256 penaltyBps = (_basePenaltyBps(v.lockDays) * daysRemaining) / lockDays;
        return (v.peakSato * penaltyBps) / BPS;
    }

    function _splitPenalty(uint256 penalty, uint256 seasonId) internal {
        uint256 toPool = (penalty * POOL_PENALTY_BPS) / BPS;
        uint256 toBurn = (penalty * BURN_PENALTY_BPS) / BPS;
        uint256 toPrize = (penalty * PRIZE_PENALTY_BPS) / BPS;
        uint256 toDev = (penalty * DEV_PENALTY_BPS) / BPS;
        // Spec routes 9800 bps explicitly; remaining 200 bps → season pool
        uint256 dust = penalty - toPool - toBurn - toPrize - toDev;

        seasonPool[seasonId] += toPool + dust;
        sato.safeTransfer(DEAD, toBurn);
        prizeFund += toPrize;
        devBalance += toDev;

        emit PrizeFunded(toPrize);
    }

    function _snapshotDrawTickets() internal {
        _clearDrawTickets();

        uint256 cumulative;
        for (uint256 id = _startTokenId(); id < _startTokenId() + totalMintedEver; id++) {
            if (!_exists(id)) continue;
            Vault storage v = vaults[id];
            if (v.satoLocked == 0 || block.timestamp >= v.lockEnd) continue;

            cumulative += v.weightAtMint;
            _drawTicketIds.push(id);
            _drawTicketCumulativeWeights.push(cumulative);
            _drawTicketOwners.push(ownerOf(id));
        }
        pendingDrawTotalWeight = cumulative;
    }

    function _winnerTicketIndex(uint256 roll) internal view returns (uint256) {
        uint256 lo;
        uint256 hi = _drawTicketCumulativeWeights.length;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            if (roll < _drawTicketCumulativeWeights[mid]) {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        }
        return lo;
    }

    function _clearDrawTickets() internal {
        delete _drawTicketIds;
        delete _drawTicketCumulativeWeights;
        delete _drawTicketOwners;
    }

    function _applyWalletCapAndSetClaims(uint256 seasonId, uint256 distributable, uint256 totalWeight)
        internal
        returns (uint256 totalAllocated)
    {
        uint256 n = totalMintedEver;
        address[] memory wallets = new address[](n);
        uint256[] memory walletRaw = new uint256[](n);
        uint256 walletCount;

        for (uint256 id = _startTokenId(); id < _startTokenId() + n; id++) {
            if (!_exists(id)) continue;
            Vault storage v = vaults[id];
            if (v.satoLocked == 0 || block.timestamp >= v.lockEnd) continue;

            address o = snapshotOwner[seasonId][id];
            uint256 raw = (distributable * v.weightAtMint) / totalWeight;
            uint256 idx = _indexOfWallet(wallets, walletCount, o);
            if (idx == type(uint256).max) {
                wallets[walletCount] = o;
                walletRaw[walletCount] = raw;
                walletCount++;
            } else {
                walletRaw[idx] += raw;
            }
        }

        uint256 walletCap = (distributable * MAX_CLAIM_BPS) / BPS;

        for (uint256 id = _startTokenId(); id < _startTokenId() + n; id++) {
            if (!_exists(id)) continue;
            Vault storage v = vaults[id];
            if (v.satoLocked == 0 || block.timestamp >= v.lockEnd) continue;

            address o = snapshotOwner[seasonId][id];
            uint256 raw = (distributable * v.weightAtMint) / totalWeight;
            uint256 idx = _indexOfWallet(wallets, walletCount, o);
            uint256 wr = walletRaw[idx];
            uint256 paid = raw;
            if (wr > walletCap) {
                paid = (raw * walletCap) / wr;
            }
            claimAmount[seasonId][id] = paid;
            totalAllocated += paid;
        }
    }

    function _indexOfWallet(
        address[] memory wallets,
        uint256 walletCount,
        address target
    ) internal pure returns (uint256) {
        for (uint256 i; i < walletCount; i++) {
            if (wallets[i] == target) return i;
        }
        return type(uint256).max;
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

    function _seasonEnd(uint256 seasonId) internal view returns (uint256) {
        return t0 + (seasonId + 1) * SEASON_DURATION;
    }

    function _beforeTokenTransfers(address from, address to, uint256, uint256) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 seasonId = _currentSeasonId();
            uint256 end = _seasonEnd(seasonId);
            if (block.timestamp >= end - TRANSFER_LOCKOUT && block.timestamp < end) {
                revert SeasonTransferLocked();
            }
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
