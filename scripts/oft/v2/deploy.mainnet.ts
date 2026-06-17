import hre from "hardhat";
import { deployForEnv } from "./_deploy";

/**
 * Mainnet deploy entrypoint.
 *
 * Usage:
 *   # BSC (lock/unlock adapter against canonical LISTA)
 *   npx hardhat run scripts/oft/v2/deploy.mainnet.ts --network bsc
 *   # Ethereum (mint/burn OFT)
 *   npx hardhat run scripts/oft/v2/deploy.mainnet.ts --network ethereum
 *
 * Reads scripts/oft/v2/oftChainsV2.mainnet.json (falls back to the .example),
 * and ADMIN / MANAGER / PAUSER from the environment.
 */
async function main() {
  const allowed = ["bsc", "ethereum"];
  if (!allowed.includes(hre.network.name)) {
    throw new Error(`deploy.mainnet expects --network bsc|ethereum, got ${hre.network.name}`);
  }
  await deployForEnv(hre, "mainnet");
}

main()
  .then(() => console.log("Done"))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
