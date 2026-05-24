#!/usr/bin/env node
/* eslint-disable no-console */
const { execSync } = require("child_process");
const { ethers } = require("ethers");
const { artifactForDeploy } = require("./compile-vault");
const { deployVaultV2Libraries } = require("./forge-artifact");
require("dotenv").config({ path: require("path").join(process.cwd(), ".env.mainnet") });
require("dotenv").config();

const MAINNET_CHAIN_ID = 1n;
const MAINNET_SATO = "0x829f4B62EEBE12Af653b4dD4fFc480966F7d7f09";
const EIP170_MAX_BYTES = 24_576;

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
  const sato = new ethers.Contract(
    satoToken,
    ["function totalSupply() view returns (uint256)"],
    provider
  );
  const supply = await sato.totalSupply();
  if (supply < ethers.parseEther("1000000")) {
    throw new Error(`SATO totalSupply ${supply} below 1M minimum for V2 deploy`);
  }

  const devAddress = optionalAddress("DEV_ADDRESS", deployer.address);
  const prizeMinSato = ethers.parseUnits(requiredEnv("PRIZE_MIN_SATO"), 18);
  const prizeDrawInterval = Number(optionalUint("PRIZE_DRAW_INTERVAL_SECONDS", "2592000"));
  const vrfCoordinator = optionalAddress("VRF_COORDINATOR", undefined);
  const vrfKeyHash = requiredEnv("VRF_KEY_HASH");
  const vrfSubscriptionId = optionalUint("VRF_SUBSCRIPTION_ID", undefined);
  const vrfConfirmations = Number(optionalUint("VRF_CONFIRMATIONS", "3"));
  const vrfCallbackGasLimit = Number(optionalUint("VRF_CALLBACK_GAS_LIMIT", "750000"));
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

  execSync("forge build", { stdio: "inherit" });
  const { abi, bytecode, deployedBytecodeBytes } = artifactForDeploy(
    "SatoStonesVaultV2.sol",
    "SatoStonesVaultV2"
  );

  console.log("Mainnet V2 deploy parameters:");
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
    deployedBytecodeBytes,
  });

  if (dryRun) {
    console.log("Dry run: mainnet V2 parameters validated");
    return;
  }
  if (!confirmed) {
    throw new Error("Refusing mainnet deploy without --confirm-mainnet");
  }
  if (deployedBytecodeBytes > EIP170_MAX_BYTES) {
    throw new Error(
      `SatoStonesVaultV2 bytecode ${deployedBytecodeBytes} bytes exceeds EIP-170 (${EIP170_MAX_BYTES}). ` +
        "Extract libraries or trim features before mainnet deploy."
    );
  }

  const libraries = await deployVaultV2Libraries(deployer, artifactForDeploy);
  const factory = new ethers.ContractFactory(abi, bytecode, deployer);
  const vault = await factory.deploy(...args, { libraries });
  await vault.waitForDeployment();
  console.log("SatoStonesVaultV2:", await vault.getAddress());
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
