import hre, { ethers } from "hardhat";
import {
  CONFIG_TYPE_EXECUTOR,
  CONFIG_TYPE_ULN,
  ENDPOINT_ABI,
  Env,
  encodeExecutorConfig,
  encodeUlnConfig,
  getChainByNetwork,
  loadChains,
} from "./utils";

/**
 * Configures the LayerZero send/receive libraries and the DVN (ULN) + executor
 * settings for the current network, for every remote peer in the config.
 *
 * DVN policy (see oftChainsV2.*.example.json `ulnConfig`):
 *   requiredDVNs  : DVNs that MUST verify every message
 *   optionalDVNs  : additional DVNs; `optionalDVNThreshold` of them must verify
 * The mainnet example uses LayerZero Labs + Nethermind + Google as required (3)
 * and USDT0 as optional (1, threshold 1).
 *
 * Must be run by the OApp delegate (MANAGER) — endpoint.setConfig / setSendLibrary
 * / setReceiveLibrary are delegate-gated on the LayerZero endpoint.
 *
 * Usage:
 *   OFT_ENV=mainnet npx hardhat run scripts/oft/v2/setDVNConfig.ts --network bsc
 *   OFT_ENV=testnet npx hardhat run scripts/oft/v2/setDVNConfig.ts --network sepolia
 */
async function main() {
  const env = (process.env.OFT_ENV || "testnet") as Env;
  const local = getChainByNetwork(env, hre.network.name);
  if (!local.proxy || local.proxy === "PENDING_DEPLOY") {
    throw new Error(`local proxy not deployed for ${local.network}`);
  }

  const signer = (await ethers.getSigners())[0];
  const endpoint = new ethers.Contract(local.lzEndpoint, ENDPOINT_ABI, signer);

  const ulnBytes = encodeUlnConfig(local);
  const execBytes = encodeExecutorConfig(local);

  const remotes = loadChains(env).filter((c) => c.eid !== local.eid);
  for (const remote of remotes) {
    console.log(`\nConfiguring ${local.network} <-> ${remote.network} (eid ${remote.eid})`);

    // outbound: send library + executor + uln for the destination eid
    let tx = await endpoint.setSendLibrary(local.proxy, remote.eid, local.sendLib);
    console.log("  setSendLibrary tx:", tx.hash);
    await tx.wait();

    tx = await endpoint.setConfig(local.proxy, local.sendLib, [
      { eid: remote.eid, configType: CONFIG_TYPE_EXECUTOR, config: execBytes },
      { eid: remote.eid, configType: CONFIG_TYPE_ULN, config: ulnBytes },
    ]);
    console.log("  setConfig(send: executor + uln) tx:", tx.hash);
    await tx.wait();

    // inbound: receive library + uln for the source (remote) eid
    tx = await endpoint.setReceiveLibrary(local.proxy, remote.eid, local.receiveLib, 0);
    console.log("  setReceiveLibrary tx:", tx.hash);
    await tx.wait();

    tx = await endpoint.setConfig(local.proxy, local.receiveLib, [
      { eid: remote.eid, configType: CONFIG_TYPE_ULN, config: ulnBytes },
    ]);
    console.log("  setConfig(receive: uln) tx:", tx.hash);
    await tx.wait();
  }
}

main()
  .then(() => console.log("Done"))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
