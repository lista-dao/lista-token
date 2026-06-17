import hre, { ethers } from "hardhat";
import { Env, getChainByNetwork, toTransferLimitTuple } from "./utils";

/**
 * Pushes the transfer limit configurations for the current network from the
 * chains config. Must be run by an account holding MANAGER_ROLE.
 *
 * Usage:
 *   OFT_ENV=mainnet npx hardhat run scripts/oft/v2/setTransferLimit.ts --network bsc
 *   OFT_ENV=testnet npx hardhat run scripts/oft/v2/setTransferLimit.ts --network sepolia
 */
async function main() {
  const env = (process.env.OFT_ENV || "testnet") as Env;
  const local = getChainByNetwork(env, hre.network.name);
  if (!local.proxy || local.proxy === "PENDING_DEPLOY") {
    throw new Error(`local proxy not deployed for ${local.network}`);
  }

  const limits = (local.transferLimits || []).map(toTransferLimitTuple);
  if (limits.length === 0) {
    console.log("no transfer limits configured, nothing to do");
    return;
  }

  const contract = await ethers.getContractAt(local.contract, local.proxy);
  const tx = await contract.setTransferLimitConfigs(limits);
  console.log(`setTransferLimitConfigs on ${local.network} tx:`, tx.hash);
  await tx.wait();
}

main()
  .then(() => console.log("Done"))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
