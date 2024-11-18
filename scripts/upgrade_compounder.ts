import { upgradeProxy, validateUpgrade } from "./tasks";
import hre from "hardhat";

const proxyAddress = "0x07eEb2981Bc28783B4977998117f70B53E172024";

async function main() {
  //validateUpgrade(hre, "contracts/old/VeListaAutoCompounder.sol:VeListaAutoCompounder", "contracts/VeListaAutoCompounder.sol:VeListaAutoCompounder");
  //const oldCompounder = await hre.ethers.getContractFactory("contracts/old/VeListaAutoCompounder.sol:VeListaAutoCompounder");
  //await hre.upgrades.forceImport(proxyAddress, oldCompounder);

  await upgradeProxy(
    hre,
    "contracts/VeListaAutoCompounder.sol:VeListaAutoCompounder",
    proxyAddress
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
