import hre, { ethers } from "hardhat";
import { getChainByNetworkName } from "./utils";

async function main() {
  const network = hre.network.name;
  console.log("Source Network: ", network);
  const chain = getChainByNetworkName(network);
  const Contract = await ethers.getContractFactory(chain.contract);
  const contract = Contract.attach(chain.oft);
  // set multi sig
  const tx = await contract.setDelegate(chain.multiSig);
  console.log("tx hash: ", tx.hash);
  await tx.wait(3);
  console.log(`Delegator is set for OFT at chain ${chain.network}`);
}

main()
  .then(() => {
    console.log("Done");
  })
  .catch(console.error);
