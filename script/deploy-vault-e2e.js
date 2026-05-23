#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");
const { compileAll, artifact } = require("./compile-vault");
require("dotenv").config({ path: path.join(process.cwd(), ".env.sepolia") });
require("dotenv").config();

async function deploy(name, contracts, sourceName, contractName, signer, args = []) {
  const { abi, bytecode } = artifact(contracts, sourceName, contractName);
  const factory = new ethers.ContractFactory(abi, bytecode, signer);
  const contract = await factory.deploy(...args);
  await contract.waitForDeployment();
  const address = await contract.getAddress();
  console.log(`${name}: ${address}`);
  return contract;
}

async function main() {
  if (process.argv.includes("--dry-run")) {
    compileAll();
    console.log("Dry run: vault compile OK");
    return;
  }

  const rpc = process.env.SEPOLIA_RPC_URL;
  const pk = process.env.SEPOLIA_PRIVATE_KEY || process.env.DEPLOYER_PRIVATE_KEY;
  if (!rpc || !pk) {
    throw new Error(
      "Set SEPOLIA_RPC_URL and DEPLOYER_PRIVATE_KEY (or SEPOLIA_PRIVATE_KEY) in .env.sepolia"
    );
  }

  const contracts = compileAll();
  const provider = new ethers.JsonRpcProvider(rpc);
  const deployer = new ethers.Wallet(pk, provider);
  const chain = await provider.getNetwork();
  if (chain.chainId !== 11155111n) {
    throw new Error(`Expected Sepolia (11155111), got chainId=${chain.chainId.toString()}`);
  }

  console.log("Deployer:", deployer.address);

  const sato = await deploy(
    "MockERC20",
    contracts,
    "src/mocks/MockERC20.sol",
    "MockERC20",
    deployer
  );
  const vrf = await deploy(
    "MockVRFCoordinator",
    contracts,
    "src/mocks/MockVRFCoordinator.sol",
    "MockVRFCoordinator",
    deployer
  );
  const vault = await deploy(
    "SatoStonesVault",
    contracts,
    "src/SatoStonesVault.sol",
    "SatoStonesVault",
    deployer,
    [
      await sato.getAddress(),
      deployer.address,
      ethers.parseEther("1000"),
      7 * 24 * 60 * 60,
      await vrf.getAddress(),
      ethers.id("key"),
      1n,
      3,
      250000,
      "ipfs://vault/",
    ]
  );

  await (await sato.mint(deployer.address, ethers.parseEther("1000000"))).wait();

  const vaultAddr = await vault.getAddress();
  const satoAddr = await sato.getAddress();
  const vrfAddr = await vrf.getAddress();

  fs.writeFileSync(
    path.join(process.cwd(), "web", "config.js"),
    `window.SATO_STONES_CONFIG = {
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
  console.log("Updated web/config.js");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
