#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");
const solc = require("solc");
const { forgeArtifact, EIP170_MAX_BYTES } = require("./forge-artifact");

const PROJECT_ROOT = process.cwd();
const REMAPPINGS = [
  ["@openzeppelin/contracts/", "lib/openzeppelin-contracts/contracts/"],
  ["erc721a/", "lib/ERC721A/contracts/"],
];

const ENTRYPOINTS = [
  "src/SatoStonesVault.sol",
  "src/SatoStonesVaultV2.sol",
  "src/mocks/MockERC20.sol",
  "src/mocks/MockVRFCoordinator.sol",
];

const ARTIFACT_TARGETS = [
  { source: "src/SatoStonesVault.sol", name: "SatoStonesVault", file: "SatoStonesVault.json" },
  { source: "src/SatoStonesVaultV2.sol", name: "SatoStonesVaultV2", file: "SatoStonesVaultV2.json" },
];

function readUtf8(p) {
  return fs.readFileSync(p, "utf8");
}

function resolveImport(importPath) {
  for (const [prefix, mappedDir] of REMAPPINGS) {
    if (importPath.startsWith(prefix)) {
      const candidate = path.join(PROJECT_ROOT, mappedDir, importPath.slice(prefix.length));
      if (fs.existsSync(candidate)) return candidate;
    }
  }
  const candidates = [
    path.join(PROJECT_ROOT, importPath),
    path.join(PROJECT_ROOT, "src", importPath),
    path.join(PROJECT_ROOT, "src/interfaces", importPath),
    path.join(PROJECT_ROOT, "src/mocks", importPath),
    path.join(PROJECT_ROOT, "src/base", importPath),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

function compileAll() {
  const sources = {};
  for (const entry of ENTRYPOINTS) {
    const absolute = path.join(PROJECT_ROOT, entry);
    sources[entry] = { content: readUtf8(absolute) };
  }

  const input = {
    language: "Solidity",
    sources,
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true,
      outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } },
    },
  };

  const output = JSON.parse(
    solc.compile(JSON.stringify(input), {
      import: (importPath) => {
        const resolved = resolveImport(importPath);
        if (!resolved) return { error: "File not found: " + importPath };
        return { contents: readUtf8(resolved) };
      },
    })
  );

  if (output.errors?.length) {
    const fatal = output.errors.filter((e) => e.severity === "error");
    if (fatal.length) {
      console.error(fatal.map((e) => e.formattedMessage).join("\n"));
      process.exit(1);
    }
    console.warn(output.errors.map((e) => e.formattedMessage).join("\n"));
  }

  const outDir = path.join(PROJECT_ROOT, "artifacts");
  fs.mkdirSync(outDir, { recursive: true });
  for (const target of ARTIFACT_TARGETS) {
    const contract = output.contracts[target.source]?.[target.name];
    if (!contract) {
      throw new Error(`Missing compile output for ${target.source}:${target.name}`);
    }
    const bytecode = contract.evm.bytecode.object;
    const bytes = bytecode.length / 2;
    if (bytes > EIP170_MAX_BYTES) {
      console.warn(
        `WARNING: ${target.name} is ${bytes} bytes (limit ${EIP170_MAX_BYTES}) — mainnet deploy may fail`
      );
    }
    fs.writeFileSync(
      path.join(outDir, target.file),
      JSON.stringify({ abi: contract.abi, bytecode: `0x${bytecode}` }, null, 2)
    );
    console.log(`Compiled ${target.name} -> artifacts/${target.file}`);
  }
  return output.contracts;
}

function artifact(contracts, sourceName, contractName) {
  const hit = contracts?.[sourceName]?.[contractName];
  if (!hit) {
    throw new Error(`Missing artifact for ${sourceName}:${contractName}`);
  }
  return {
    abi: hit.abi,
    bytecode: `0x${hit.evm.bytecode.object}`,
  };
}

/** Prefer Foundry artifact when `out/` exists (canonical for deploy). */
function artifactForDeploy(sourceFile, contractName) {
  const forgePath = path.join(process.cwd(), "out", sourceFile, `${contractName}.json`);
  if (fs.existsSync(forgePath)) {
    return forgeArtifact(sourceFile, contractName);
  }
  const contracts = compileAll();
  return artifact(contracts, sourceFile, contractName);
}

if (require.main === module) {
  compileAll();
}

module.exports = { compileAll, artifact, artifactForDeploy, forgeArtifact };
