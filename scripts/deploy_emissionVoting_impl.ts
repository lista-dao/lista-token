import { deployDirect } from "./tasks";
import hre from "hardhat";

async function main() {
  await deployDirect(hre, "EmissionVoting");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
