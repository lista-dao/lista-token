import { upgradeProxy, validateUpgrade } from "./tasks";
import hre from "hardhat";

const proxyAddress = "0x79B3286c318bdf7511A59dcf9a2E88882064eCbA";

async function main() {
  // await deployDirect(hre, "ListaToken", owner);
  validateUpgrade(hre, "contracts/old/VeLista.sol:VeLista", "contracts/VeLista.sol:VeLista");
  const oldVeLista = await hre.ethers.getContractFactory("contracts/old/VeLista.sol:VeLista");
  await hre.upgrades.forceImport(proxyAddress, oldVeLista);

  await upgradeProxy(
    hre,
    "contracts/VeLista.sol:VeLista",
    proxyAddress
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
