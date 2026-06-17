import hre from "hardhat";
import { deployForEnv } from "./_deploy";

/**
 * Testnet deploy entrypoint.
 *
 * Usage:
 *   # BSC Testnet (lock/unlock adapter against test LISTA)
 *   npx hardhat run scripts/oft/v2/deploy.testnet.ts --network bscTestnet
 *   # Sepolia (mint/burn OFT)
 *   npx hardhat run scripts/oft/v2/deploy.testnet.ts --network sepolia
 *
 * Reads scripts/oft/v2/oftChainsV2.testnet.json (falls back to the .example),
 * and ADMIN / MANAGER / PAUSER from the environment.
 *
 * Test LISTA @ BSC Testnet: 0x90b94D605E069569Adf33C0e73E26a83637c94B1
 */
async function main() {
  const allowed = ["bscTestnet", "sepolia"];
  if (!allowed.includes(hre.network.name)) {
    throw new Error(`deploy.testnet expects --network bscTestnet|sepolia, got ${hre.network.name}`);
  }
  await deployForEnv(hre, "testnet");
}

main()
  .then(() => console.log("Done"))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
