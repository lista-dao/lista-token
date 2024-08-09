import { deployProxy } from "./tasks";
import hre from "hardhat";

const admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  const oracle = "0x6AEfe49ECDE3EaEeAA15328f11F84C483602B311";
  await deployProxy(hre, "OracleCenter", admin, oracle);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
