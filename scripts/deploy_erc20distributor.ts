import { deployProxy } from "./tasks";
import hre from "hardhat";

const admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  const listaVault = "0x5C25A9FC1CFfda5D7E871C73929Dfca85ef6c92d";
  const lpToken = "0xb2aa63f363196caba3154d4187949283f085a488";
  await deployProxy(hre, "ERC20LpListaDistributor", admin, admin, listaVault, lpToken);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
