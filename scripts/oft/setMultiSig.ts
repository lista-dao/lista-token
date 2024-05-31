import hre, { ethers } from "hardhat";
import { getChainByEid } from "./utils";

/**
 * BSC Testnet: 40102 | Sepolia: 40161 | opBNB Testnet: 40202
 */
const sourceChainId = 40161;

async function main() {
  const network = hre.network.name;
  console.log("Source Network: ", network);
  const chain = getChainByEid(sourceChainId);
  const Contract = await ethers.getContractFactory(chain.contract);
  const contract = Contract.attach(chain.oft);
  // set multi sig
  const tx = await contract.setMultiSig(chain.multiSig);
  console.log("tx hash: ", tx.hash);
  await tx.wait(3);
  console.log(`Multi-sig is set for OFT at chain ${chain.network}`);
}

main()
  .then(() => {
    console.log("Done");
  })
  .catch(console.error);
