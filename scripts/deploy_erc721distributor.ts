import { deployProxy } from "./tasks";
import hre from "hardhat";

const admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  let nftManager;
  if (hre.network.name === "bsc") {
    nftManager = "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364";
    // slisBNB/BNB v3 LP 0.05%
    await deployERC721Distributor(
      "slisBNB/BNB v3 LP",
      nftManager,
      "0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B",
      "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
      500,
      "50000000000000000" // 5 * 10 ** 16
    );
    // lisUSD/WBNB v3 LP 0.25%
    await deployERC721Distributor(
      "lisUSD/WBNB v3 LP",
      nftManager,
      "0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5",
      "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
      2500,
      "100000000000000000" // 10 ** 17
    );
    // lisUSD/BTCB v3 LP 0.25%
    await deployERC721Distributor(
      "lisUSD/BTCB v3 LP",
      nftManager,
      "0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5",
      "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c",
      2500,
      "100000000000000000" // 10 ** 17
    );
    // lisUSD/ETH v3 LP 0.25%
    await deployERC721Distributor(
      "lisUSD/ETH v3 LP",
      nftManager,
      "0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5",
      "0x2170Ed0880ac9A755fd29B2688956BD959F933F8",
      2500,
      "100000000000000000" // 10 ** 17
    );
    // lisUSD/USDT v3 LP 0.05%
    await deployERC721Distributor(
      "lisUSD/USDT v3 LP",
      nftManager,
      "0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5",
      "0x55d398326f99059fF775485246999027B3197955",
      500,
      "30000000000000000" // 3 * 10 ** 16
    );
  } else if (hre.network.name === "bscTestnet") {
    nftManager = "0x427bF5b37357632377eCbEC9de3626C71A5396c1";
    // slisBNB/BNB v3 LP 0.05%
    await deployERC721Distributor(
      "slisBNB/BNB v3 LP",
      nftManager,
      "0x785b5d1Bde70bD6042877cA08E4c73e0a40071af",
      "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
      2500,
      "100000000000000000" // 10 ** 17
    );
    // lisUSD/WBNB v3 LP 0.25%
    await deployERC721Distributor(
      "lisUSD/WBNB v3 LP",
      nftManager,
      "0x785b5d1Bde70bD6042877cA08E4c73e0a40071af",
      "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
      2500,
      "100000000000000000" // 10 ** 17
    );
    // lisUSD/BTCB v3 LP 0.25%
    await deployERC721Distributor(
      "lisUSD/BTCB v3 LP",
      nftManager,
      "0x785b5d1Bde70bD6042877cA08E4c73e0a40071af",
      "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
      2500,
      "100000000000000000" // 10 ** 17
    );
    // lisUSD/ETH v3 LP 0.25%
    await deployERC721Distributor(
      "lisUSD/ETH v3 LP",
      nftManager,
      "0x785b5d1Bde70bD6042877cA08E4c73e0a40071af",
      "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd",
      2500,
      "100000000000000000" // 10 ** 17
    );
  }
}

async function deployERC721Distributor(
  name: any,
  lpToken: any,
  token0: any,
  token1: any,
  fee: any,
  percentRate: any
) {
  let listaVault, oracleCenter;
  if (hre.network.name === "bsc") {
    listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
    oracleCenter = "0x946a68b29149f819FBcE866cED3632e0C9F7C53b";
  } else if (hre.network.name === "bscTestnet") {
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
    oracleCenter = "0x8A84a7D0f7a9dE22b5B91B6B45D450cf7F057168";
  }
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  const address = await deployProxy(
    hre,
    "ERC721LpListaDistributor",
    deployer,
    deployer,
    listaVault,
    lpToken,
    oracleCenter,
    token0,
    token1,
    fee,
    percentRate
  );
  const contract = await hre.ethers.getContractAt("ListaVault", listaVault);

  await contract.registerDistributor(address);

  console.log(`${name} deployed to: ${address}`);
  await contract.waitForDeployment();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
