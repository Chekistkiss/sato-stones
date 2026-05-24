#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
const { ethers } = require("ethers");
const { artifactForDeploy } = require("./compile-vault");
const { deployVaultV2Libraries } = require("./forge-artifact");
require("dotenv").config({ path: path.join(process.cwd(), ".env.sepolia") });
require("dotenv").config();

async function deploy(name, sourceName, contractName, signer, args = [], libraries) {
  const { abi, bytecode } = artifactForDeploy(sourceName, contractName);
  const factory = new ethers.ContractFactory(abi, bytecode, signer);
  const contract = libraries
    ? await factory.deploy(...args, { libraries })
    : await factory.deploy(...args);
  await contract.waitForDeployment();
  const address = await contract.getAddress();
  console.log(`${name}: ${address}`);
  return contract;
}

async function main() {
  if (process.argv.includes("--dry-run")) {
    execSync("forge build", { stdio: "inherit" });
    const art = artifactForDeploy("SatoStonesVaultV2.sol", "SatoStonesVaultV2");
    console.log("Dry run: forge build OK; V2 deployed runtime bytes:", art.deployedBytecodeBytes);
    return;
  }

  const rpc = process.env.SEPOLIA_RPC_URL;
  const pk = process.env.SEPOLIA_PRIVATE_KEY || process.env.DEPLOYER_PRIVATE_KEY;
  if (!rpc || !pk) {
    throw new Error(
      "Set SEPOLIA_RPC_URL and DEPLOYER_PRIVATE_KEY (or SEPOLIA_PRIVATE_KEY) in .env.sepolia"
    );
  }

  execSync("forge build", { stdio: "inherit" });

  const provider = new ethers.JsonRpcProvider(rpc);
  const deployer = new ethers.Wallet(pk, provider);
  const chain = await provider.getNetwork();
  if (chain.chainId !== 11155111n) {
    throw new Error(`Expected Sepolia (11155111), got chainId=${chain.chainId.toString()}`);
  }

  console.log("Deployer:", deployer.address);

  const libraries = await deployVaultV2Libraries(deployer, artifactForDeploy);

  const sato = await deploy("MockERC20", "src/mocks/MockERC20.sol", "MockERC20", deployer);
  const vrf = await deploy(
    "MockVRFCoordinator",
    "src/mocks/MockVRFCoordinator.sol",
    "MockVRFCoordinator",
    deployer
  );
  const vault = await deploy(
    "SatoStonesVaultV2",
    "SatoStonesVaultV2.sol",
    "SatoStonesVaultV2",
    deployer,
    [
      await sato.getAddress(),
      deployer.address,
      ethers.parseEther("10"),
      30 * 24 * 60 * 60,
      await vrf.getAddress(),
      ethers.id("key"),
      1n,
      3,
      750_000,
      "ipfs://vault-v2/",
    ],
    libraries
  );

  await (await sato.mint(deployer.address, ethers.parseEther("1000000"))).wait();

  const vaultAddr = await vault.getAddress();
  const satoAddr = await sato.getAddress();
  const vrfAddr = await vrf.getAddress();

  fs.writeFileSync(
    path.join(process.cwd(), "web", "config.js"),
    `window.SATO_STONES_CONFIG = {
  vaultVersion: 2,
  contractAddress: "${vaultAddr}",
  satoTokenAddress: "${satoAddr}",
  vrfAddress: "${vrfAddr}",
  chainId: 11155111,
  chainName: "Sepolia",
  rpcUrls: ["https://ethereum-sepolia-rpc.publicnode.com"],
  explorerBaseUrl: "https://sepolia.etherscan.io",
  maxSupply: 2100,
};
`
  );
  console.log("Updated web/config.js (vaultVersion: 2)");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
