#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");

const EIP170_MAX_BYTES = 24_576;

function resolveArtifactPath(contractFile, contractName) {
  const candidates = [
    path.join(process.cwd(), "out", contractFile, `${contractName}.json`),
    path.join(
      process.cwd(),
      "out",
      path.basename(contractFile),
      `${contractName}.json`
    ),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

function forgeArtifact(contractFile, contractName) {
  const jsonPath = resolveArtifactPath(contractFile, contractName);
  if (!jsonPath) {
    throw new Error(
      `Missing artifact for ${contractFile}:${contractName}. Run: forge build`
    );
  }
  const raw = JSON.parse(fs.readFileSync(jsonPath, "utf8"));
  const creation = raw.bytecode?.object;
  const deployed = raw.deployedBytecode?.object;
  if (!creation) throw new Error(`No bytecode in ${jsonPath}`);
  const deployedHex = deployed || creation;
  const bytes =
    (deployedHex.startsWith("0x") ? deployedHex.length - 2 : deployedHex.length) / 2;
  if (bytes > EIP170_MAX_BYTES) {
    console.warn(
      `WARNING: ${contractName} deployed runtime is ${bytes} bytes (EIP-170 limit ${EIP170_MAX_BYTES}).`
    );
  }
  return {
    abi: raw.abi,
    bytecode: creation.startsWith("0x") ? creation : `0x${creation}`,
    linkReferences: raw.bytecode?.linkReferences || {},
    deployedBytecodeBytes: bytes,
  };
}

/** Deploy linked libraries required by SatoStonesVaultV2; returns ethers library map. */
async function deployVaultV2Libraries(signer, artifactForDeployFn) {
  const libs = [
    ["src/libraries/VaultSeasonLib.sol", "VaultSeasonLib"],
    ["src/libraries/VaultLotteryLib.sol", "VaultLotteryLib"],
    ["src/libraries/VaultGenesisLib.sol", "VaultGenesisLib"],
  ];
  const libraries = {};
  for (const [source, name] of libs) {
    const { abi, bytecode } = artifactForDeployFn(source, name);
    const factory = new (require("ethers")).ContractFactory(abi, bytecode, signer);
    const c = await factory.deploy();
    await c.waitForDeployment();
    const addr = await c.getAddress();
    libraries[`${source}:${name}`] = addr;
    console.log(`${name}: ${addr}`);
  }
  return libraries;
}

module.exports = {
  forgeArtifact,
  EIP170_MAX_BYTES,
  deployVaultV2Libraries,
};
