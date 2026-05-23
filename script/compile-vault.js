#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");
const solc = require("solc");

const PROJECT_ROOT = process.cwd();
const REMAPPINGS = [
  ["@openzeppelin/contracts/", "lib/openzeppelin-contracts/contracts/"],
  ["erc721a/", "lib/ERC721A/contracts/"],
];

const ENTRYPOINTS = [
  "src/SatoStonesVault.sol",
  "src/mocks/MockERC20.sol",
  "src/mocks/MockVRFCoordinator.sol",
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

  const contract = output.contracts["src/SatoStonesVault.sol"]["SatoStonesVault"];
  const outDir = path.join(PROJECT_ROOT, "artifacts");
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(
    path.join(outDir, "SatoStonesVault.json"),
    JSON.stringify({ abi: contract.abi, bytecode: contract.evm.bytecode.object }, null, 2)
  );
  console.log("Compiled SatoStonesVault -> artifacts/SatoStonesVault.json");
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

if (require.main === module) {
  compileAll();
}

module.exports = { compileAll, artifact };
