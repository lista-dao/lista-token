import { deployProxy } from "./tasks";
import hre from "hardhat";

const admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  const listaVault = "0xCfeb269242cf988b61833910E7aaC56554F09f7b";
  const lpToken = "0x427bF5b37357632377eCbEC9de3626C71A5396c1";
  const oracleCenter = "0x8A84a7D0f7a9dE22b5B91B6B45D450cf7F057168";
  const token0 = "0x785b5d1Bde70bD6042877cA08E4c73e0a40071af";
  const token1 = "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd";
  const fee = 2500;
  const percentRate = "10000000000000000";
  await deployProxy(hre, "ERC721LpListaDistributor", admin, admin, listaVault, lpToken, oracleCenter, token0 , token1, fee, percentRate);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
