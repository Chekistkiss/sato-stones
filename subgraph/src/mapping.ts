import { BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  StoneMinted,
  SeasonFinalized,
  SeasonClaimed,
  PrizeAssigned,
  RoyaltyDistributed,
} from "../generated/SatoStonesVaultV2/SatoStonesVaultV2";
import { Stone, Season, SeasonClaim, PrizeDraw, RoyaltyDistribution } from "../generated/schema";

function stoneId(tokenId: BigInt): string {
  return tokenId.toString();
}

function seasonEntityId(seasonId: BigInt): string {
  return seasonId.toString();
}

export function handleStoneMinted(event: StoneMinted): void {
  let stone = new Stone(stoneId(event.params.tokenId));
  stone.tokenId = event.params.tokenId;
  stone.minter = event.params.minter;
  stone.owner = event.params.minter;
  stone.originalMinter = event.params.minter;
  stone.peakSato = event.params.peakSato;
  stone.satoLocked = event.params.peakSato;
  stone.mintTime = event.params.mintTime;
  stone.lockEnd = event.params.lockEnd;
  stone.weightAtMint = BigInt.fromI32(event.params.weightAtMint);
  stone.lockDays = 0;
  stone.rarity = 0;
  stone.isGenesis = false;
  stone.genesisRank = 0;
  stone.redeemed = false;
  stone.save();
}

export function handleSeasonFinalized(event: SeasonFinalized): void {
  let season = new Season(seasonEntityId(event.params.seasonId));
  season.seasonId = event.params.seasonId;
  season.distributable = event.params.distributable;
  season.totalEffectiveWeight = event.params.totalEffectiveWeight;
  season.finalized = true;
  season.closed = false;
  season.save();
}

export function handleSeasonClaimed(event: SeasonClaimed): void {
  let id =
    seasonEntityId(event.params.seasonId) +
    "-" +
    event.params.tokenId.toString();
  let claim = new SeasonClaim(id);
  claim.seasonId = event.params.seasonId;
  claim.tokenId = event.params.tokenId;
  claim.claimant = event.params.claimant;
  claim.amount = event.params.amount;
  claim.save();
}

export function handlePrizeAssigned(event: PrizeAssigned): void {
  let id = event.params.drawId.toString() + "-" + event.params.place.toString();
  let draw = new PrizeDraw(id);
  draw.drawId = event.params.drawId;
  draw.requestId = BigInt.zero();
  draw.amount = event.params.amount;
  draw.winner = event.params.winner;
  draw.place = event.params.place;
  draw.winnerAmount = event.params.amount;
  draw.save();
}

export function handleRoyaltyDistributed(event: RoyaltyDistributed): void {
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let royalty = new RoyaltyDistribution(id);
  royalty.royaltyIn = event.params.royaltyIn;
  royalty.poolAmount = event.params.poolAmount;
  royalty.devAmount = event.params.devAmount;
  royalty.genesisAmount = event.params.genesisAmount;
  royalty.checkpointIdx = event.params.checkpointIdx;
  royalty.timestamp = event.block.timestamp;
  royalty.save();
}
