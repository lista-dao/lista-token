import { deployProxy } from "./tasks";
import hre from "hardhat";
import moment from "moment";

const admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";
const manager = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  // await deployDirect(hre, "ListaToken", owner);

  const startTime = moment.utc("2024-05-22", "YYYY-MM-DD");
  console.log(startTime.unix());
  const listaToken = "0x1d6d362f3b2034D9da97F0d1BE9Ff831B7CC71EB";
  await deployProxy(hre, "VeLista", admin, manager, startTime.unix(), listaToken, manager);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
