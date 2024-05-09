import { deployProxy } from "./tasks";
import hre from "hardhat";

const admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  const listaVault = "0xCfeb269242cf988b61833910E7aaC56554F09f7b";
  const lpToken = "0x1d6d362f3b2034D9da97F0d1BE9Ff831B7CC71EB";
  await deployProxy(hre, "ERC20LpListaDistributor", admin, admin, listaVault, lpToken);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
