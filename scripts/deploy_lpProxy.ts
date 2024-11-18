import { deployDirect, deployProxy } from "./tasks";
import hre from "hardhat";
import Promise from "bluebird";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  // todo
  const pancakeVault = "";
  const thenaVault = "";
  const listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
  const address = await deployProxy(hre, "LpProxy", deployer);

  const contract = await hre.ethers.getContractAt("LpProxy", address);

  await contract.setListaVault(listaVault);
  await contract.setCakeVault(pancakeVault);
  await contract.setThenaVault(thenaVault);

  await Promise.delay(3000);

  const pancakeDistributors = ["0xe8f4644637f127aFf11F9492F41269eB5e8b8dD2"];
  const thenaDistributors = [
    "0xFf5ed1E64aCA62c822B178FFa5C36B40c112Eb00",
    "0x1Cf9c6D475CdcA67942d41B0a34BD9cB9D336C4d",
    "0xC23d348f9cC86dDB059ec798e87E7F76FBC077C1",
    "0x9B4FcbC3a01378B85d81DEFbaf9359155718be4a",
    "0x11bf1122871e13c13466681022C74B496B59147a",
    "0x39D099F6A78c7Cef7a527f55c921E7e1EE39716a",
    "0x9f6C251C3122207Adf561714C1171534B569eFf4",
    "0xF6aB5cfdB46357f37b0190b793fB199D62Dcf504",
  ];

  for (const distributor of pancakeDistributors) {
    console.log(`distributor: ${distributor} pancakeVault: ${pancakeVault}`);
    await contract.setDistributorToVault(distributor, pancakeVault);
  }

  for (const distributor of thenaDistributors) {
    console.log(`distributor: ${distributor} thenaVault: ${thenaVault}`);
    await contract.setDistributorToVault(distributor, thenaVault);
  }

  const pancakeVaultContract = await hre.ethers.getContractAt(
    "StakingVault",
    pancakeVault
  );

  const thenaVaultContract = await hre.ethers.getContractAt(
    "StakingVault",
    thenaVault
  );

  await pancakeVaultContract.setLpProxy(address);
  await thenaVaultContract.setLpProxy(address);

  console.log("deploy and setup contract done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
