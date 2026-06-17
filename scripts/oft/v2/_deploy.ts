import { HardhatRuntimeEnvironment } from "hardhat/types";
import {
  Env,
  ChainConfig,
  getChainByNetwork,
  getRoles,
  loadChains,
  saveChains,
  toTransferLimitTuple,
} from "./utils";

/**
 * Deploys the upgradeable Lista OFT contract for the current network.
 *
 *  - ListaOFTAdapterV2 (lock/unlock) on the canonical home chain (BSC). The
 *    implementation bakes in the immutable (token, lzEndpoint); initialize sets
 *    roles + transfer limits.
 *  - ListaOFTv2 (mint/burn) on remote chains (ETH). The implementation bakes in
 *    the immutable (lzEndpoint); initialize sets name/symbol + roles + limits.
 *
 * Uses a UUPS proxy; only DEFAULT_ADMIN_ROLE can authorize upgrades.
 * Writes the resulting proxy address back into the live chains config.
 */
export async function deployForEnv(hre: HardhatRuntimeEnvironment, env: Env): Promise<string> {
  const { ethers, upgrades, network } = hre;
  const chain = getChainByNetwork(env, network.name);
  const { admin, manager, pauser } = getRoles();

  console.log(`\n=== Deploying ${chain.contract} on ${network.name} (${env}) ===`);
  console.log("admin:  ", admin);
  console.log("manager:", manager);
  console.log("pauser: ", pauser);
  console.log("lzEndpoint:", chain.lzEndpoint);

  const limits = (chain.transferLimits || []).map(toTransferLimitTuple);

  let proxyAddress: string;
  let constructorArgs: unknown[];

  if (chain.contract === "ListaOFTAdapterV2") {
    const token = chain.existingTokenAddress;
    if (!token) throw new Error("existingTokenAddress is required for the adapter chain");
    console.log("locked token:", token);

    constructorArgs = [token, chain.lzEndpoint];
    const Factory = await ethers.getContractFactory("ListaOFTAdapterV2");
    const proxy = await upgrades.deployProxy(Factory, [admin, manager, pauser, limits], {
      kind: "uups",
      initializer: "initialize",
      constructorArgs,
      unsafeAllow: ["constructor", "state-variable-immutable"],
    });
    await proxy.waitForDeployment();
    proxyAddress = await proxy.getAddress();
  } else {
    if (!chain.tokenName || !chain.symbol) {
      throw new Error("tokenName and symbol are required for the OFT chain");
    }
    constructorArgs = [chain.lzEndpoint];
    const Factory = await ethers.getContractFactory("ListaOFTv2");
    const proxy = await upgrades.deployProxy(
      Factory,
      [chain.tokenName, chain.symbol, admin, manager, pauser, limits],
      {
        kind: "uups",
        initializer: "initialize",
        constructorArgs,
        unsafeAllow: ["constructor", "state-variable-immutable"],
      }
    );
    await proxy.waitForDeployment();
    proxyAddress = await proxy.getAddress();
  }

  const implAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log(`${chain.contract} proxy deployed:`, proxyAddress);
  console.log("implementation:", implAddress);

  // persist proxy address back into the live config
  const all = loadChains(env);
  const updated = all.map((c: ChainConfig) =>
    c.network === network.name ? { ...c, proxy: proxyAddress } : c
  );
  saveChains(env, updated);
  console.log(`Saved proxy address into oftChainsV2.${env}.json`);

  // verify implementation (best-effort)
  try {
    console.log("Waiting 10s before verification...");
    await new Promise((r) => setTimeout(r, 10000));
    await hre.run("verify:verify", { address: implAddress, constructorArguments: constructorArgs });
  } catch (e) {
    console.warn("Verification skipped/failed:", (e as Error).message);
  }

  return proxyAddress;
}
