import { deployProxy } from "./tasks";
import hre from "hardhat";

const admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  const listaVault = "0x5C25A9FC1CFfda5D7E871C73929Dfca85ef6c92d";
  const lpToken = "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364";
  const oracleCenter = "0x85e0C3467B4329E9834F1F31CF0F4a8C17c50A4D";
  const token0 = "0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5";
  const token1 = "0x55d398326f99059fF775485246999027B3197955";
  const fee = 500;
  const percentRate = "10000000000000000";
  await deployProxy(hre, "ERC721LpListaDistributor", admin, admin, listaVault, lpToken, oracleCenter, token0 , token1, fee, percentRate);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
