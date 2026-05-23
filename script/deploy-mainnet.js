#!/usr/bin/env node
/* eslint-disable no-console */
const path = require("path");
const { ethers } = require("ethers");
const { compileAll, artifact } = require("./compile-vault");
require("dotenv").config({ path: path.join(process.cwd(), ".env.mainnet") });
require("dotenv").config();

const MAINNET_CHAIN_ID = 1n;
const MAINNET_SATO = "0x829f4B62EEBE12Af653b4dD4fFc480966F7d7f09";

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Set ${name} in .env.mainnet or environment`);
  return value;
}

function optionalAddress(name, fallback) {
  const value = process.env[name] || fallback;
  if (!ethers.isAddress(value)) throw new Error(`${name} is not a valid address`);
  return ethers.getAddress(value);
}

function optionalUint(name, fallback) {
  const value = process.env[name] || fallback;
  const parsed = BigInt(value);
  if (parsed < 0n) throw new Error(`${name} must be non-negative`);
  return parsed;
}

async function main() {
  const dryRun = process.argv.includes("--dry-run");
  const confirmed = process.argv.includes("--confirm-mainnet");

  const contracts = compileAll();
  const rpc = requiredEnv("MAINNET_RPC_URL");
  const pk = process.env.MAINNET_PRIVATE_KEY || process.env.DEPLOYER_PRIVATE_KEY;
  if (!pk) throw new Error("Set MAINNET_PRIVATE_KEY or DEPLOYER_PRIVATE_KEY");

  const provider = new ethers.JsonRpcProvider(rpc);
  const deployer = new ethers.Wallet(pk, provider);
  const chain = await provider.getNetwork();
  if (chain.chainId !== MAINNET_CHAIN_ID) {
    throw new Error(`Expected Ethereum mainnet (1), got chainId=${chain.chainId.toString()}`);
  }

  const satoToken = optionalAddress("SATO_TOKEN_ADDRESS", MAINNET_SATO);
  const devAddress = optionalAddress("DEV_ADDRESS", deployer.address);
  const prizeMinSato = ethers.parseUnits(requiredEnv("PRIZE_MIN_SATO"), 18);
  const prizeDrawInterval = Number(optionalUint("PRIZE_DRAW_INTERVAL_SECONDS", "2592000"));
  const vrfCoordinator = optionalAddress("VRF_COORDINATOR", undefined);
  const vrfKeyHash = requiredEnv("VRF_KEY_HASH");
  const vrfSubscriptionId = optionalUint("VRF_SUBSCRIPTION_ID", undefined);
  const vrfConfirmations = Number(optionalUint("VRF_CONFIRMATIONS", "3"));
  const vrfCallbackGasLimit = Number(optionalUint("VRF_CALLBACK_GAS_LIMIT", "250000"));
  const baseURI = process.env.BASE_URI || "";

  const args = [
    satoToken,
    devAddress,
    prizeMinSato,
    prizeDrawInterval,
    vrfCoordinator,
    vrfKeyHash,
    vrfSubscriptionId,
    vrfConfirmations,
    vrfCallbackGasLimit,
    baseURI,
  ];

  console.log("Mainnet deploy parameters:");
  console.log({
    deployer: deployer.address,
    satoToken,
    devAddress,
    prizeMinSato: prizeMinSato.toString(),
    prizeDrawInterval,
    vrfCoordinator,
    vrfKeyHash,
    vrfSubscriptionId: vrfSubscriptionId.toString(),
    vrfConfirmations,
    vrfCallbackGasLimit,
    baseURI,
  });

  if (dryRun) {
    console.log("Dry run: mainnet parameters validated and vault compile OK");
    return;
  }
  if (!confirmed) {
    throw new Error("Refusing mainnet deploy without --confirm-mainnet");
  }

  const { abi, bytecode } = artifact(contracts, "src/SatoStonesVault.sol", "SatoStonesVault");
  const factory = new ethers.ContractFactory(abi, bytecode, deployer);
  const vault = await factory.deploy(...args);
  await vault.waitForDeployment();
  console.log("SatoStonesVault:", await vault.getAddress());
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
