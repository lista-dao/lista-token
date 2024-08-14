import { deployProxy } from "./tasks";
import hre from "hardhat";

const admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  let oracle;
  if (hre.network.name === "bsc") {
    oracle = "0xf3afD82A4071f272F403dC176916141f44E6c750";
  } else if (hre.network.name === "bscTestnet") {
    oracle = "0x9CCf790F691925fa61b8cB777Cb35a64F5555e53";
  }
  await deployProxy(hre, "OracleCenter", admin, oracle);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
