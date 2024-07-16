import { deployProxy, transferProxyAdminOwner } from "./tasks";
import hre from "hardhat";
import { deploy } from "@openzeppelin/hardhat-upgrades/dist/utils";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  console.log(deployer);
  const veLista = "todo";
  const address = await deployProxy(hre, "VeListaDistributor", deployer, deployer, veLista);

  const contract = await hre.ethers.getContractAt("VeListaDistributor", address);
  // slisBNB
  await contract.registerNewToken("0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B", {
    gasLimit: 1000000,
  });
  // BNB
  await contract.registerNewToken("0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", {
    gasLimit: 1000000,
  });
  // ETH
  await contract.registerNewToken("0x2170Ed0880ac9A755fd29B2688956BD959F933F8", {
    gasLimit: 1000000,
  });
  // lisUSD
  await contract.registerNewToken("0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5", {
    gasLimit: 1000000,
  });
  // LISTA
  await contract.registerNewToken("0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46", {
    gasLimit: 1000000,
  });
  // WBETH
  await contract.registerNewToken("0xa2E3356610840701BDf5611a53974510Ae27E2e1", {
    gasLimit: 1000000,
  });

  console.log("done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
