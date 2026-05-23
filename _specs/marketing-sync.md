# Sato Stones — Marketing sync rules

## Canonical economics

See [sato-stones-vault-nft.md](./sato-stones-vault-nft.md).

- Max supply: **2,100** mints ever (early exit burns NFT but does not free a slot).
- Deposit: **100–10,000 SATO** per stone (plus 0.1% supply cap at mint).
- **Genesis:** first **21** mints with gross **≥ 500 SATO** (`genesisRank` 1–21); `tokenId` is sequential #1–#2100, not tied to Genesis order.
- Lock: **15 / 30 / 60 days** only.
- **2% mint fee** → season pool; **no bonding-curve sell** on mint.
- Early exit: progressive penalty on `peakSato`; split pool / burn / prize / dev per spec.
- After lock: **100% SATO** returned via `redeem`; NFT kept.

## Messaging constraints

- Do not claim "every mint burns SATO forever" — burns come from **penalties**, not mint.
- Do not use fixed tier prices (50/100/200/500) unless clearly labeled as deprecated.
- Lottery: funded from penalties; VRF draw when `prizeFund >= prizeMinSato`; winner claims via `claimPrize()`.

## Release checklist

- [ ] Site copy matches Vault spec (deposit range, Genesis rule, lock periods).
- [ ] `web/config.js` points to current Vault contract.
- [ ] FAQ: early exit vs redeem, season pool, transfer lockout last hour of season.
