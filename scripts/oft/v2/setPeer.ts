import hre, { ethers } from "hardhat";
import { Env, getChainByNetwork, loadChains, padAddress } from "./utils";

/**
 * Wires the trusted peer from the current network to every other chain in the
 * config. Must be run by an account holding MANAGER_ROLE on the local OFT.
 *
 * Usage:
 *   OFT_ENV=mainnet npx hardhat run scripts/oft/v2/setPeer.ts --network bsc
 *   OFT_ENV=testnet npx hardhat run scripts/oft/v2/setPeer.ts --network bscTestnet
 */
async function main() {
  const env = (process.env.OFT_ENV || "testnet") as Env;
  const local = getChainByNetwork(env, hre.network.name);
  if (!local.proxy || local.proxy === "PENDING_DEPLOY") {
    throw new Error(`local proxy not deployed for ${local.network}`);
  }

  const contract = await ethers.getContractAt(local.contract, local.proxy);
  const remotes = loadChains(env).filter((c) => c.eid !== local.eid);

  for (const remote of remotes) {
    if (!remote.proxy || remote.proxy === "PENDING_DEPLOY") {
      console.warn(`skip ${remote.network}: proxy not deployed`);
      continue;
    }
    const tx = await contract.setPeer(remote.eid, padAddress(remote.proxy));
    console.log(`setPeer ${local.network} -> ${remote.network} (eid ${remote.eid}) tx:`, tx.hash);
    await tx.wait();
  }
}

main()
  .then(() => console.log("Done"))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
