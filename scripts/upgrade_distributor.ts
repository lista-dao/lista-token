import { upgradeProxy, validateUpgrade } from "./tasks";
import hre from "hardhat";

const proxyAddress = "0x040037d4c8cb2784d47a75Aa20e751CDB1E8971A";

async function main() {
  // await deployDirect(hre, "ListaToken", owner);

  validateUpgrade(hre, "contracts/old/VeListaDistributor.sol:VeListaDistributor", "contracts/VeListaDistributor.sol:VeListaDistributor");
  const oldDistributor = await hre.ethers.getContractFactory("contracts/old/VeListaDistributor.sol:VeListaDistributor");
  await hre.upgrades.forceImport(proxyAddress, oldDistributor);

  await upgradeProxy(
    hre,
    "contracts/VeListaDistributor.sol:VeListaDistributor",
    proxyAddress
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
