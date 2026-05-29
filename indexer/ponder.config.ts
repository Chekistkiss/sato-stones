import { createConfig } from "ponder";
import { http } from "viem";

import { SatoStonesVaultAbi } from "./abis/SatoStonesVault";

const VAULT_ADDRESS =
  (process.env.VAULT_ADDRESS as `0x${string}` | undefined) ??
  "0xd526B4AF4e63B18c08dd9DB651B25A0433e2c846";

const VAULT_START_BLOCK = Number(process.env.VAULT_START_BLOCK ?? 10_942_134);

export default createConfig({
  chains: {
    sepolia: {
      id: 11155111,
      rpc: http(process.env.PONDER_RPC_URL_11155111),
    },
  },
  contracts: {
    SatoStonesVault: {
      chain: "sepolia",
      address: VAULT_ADDRESS,
      abi: SatoStonesVaultAbi,
      startBlock: VAULT_START_BLOCK,
    },
  },
  database: { kind: "pglite", directory: ".ponder/pglite" },
  schema: "sato_stones",
});
