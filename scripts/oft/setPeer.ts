import hre, { ethers } from "hardhat";
import { getChainByEid, padAddress } from "./utils";

/**
 * BSC Testnet: 40102 | Sepolia: 40161 | opBNB Testnet: 40202
 */
const from = 40161;
const to = 40102;

async function main() {
  const network = hre.network.name;
  console.log("Source Network: ", network);
  const chainA = getChainByEid(from);
  const chainB = getChainByEid(to);
  const Contract = await ethers.getContractFactory(chainA.contract);
  const contract = Contract.attach(chainA.oft);
  // set peer
  const tx = await contract.setPeer(chainB.eid, padAddress(chainB.oft));
  console.log("tx hash: ", tx.hash);
  await tx.wait(3);
  console.log(
    `Chain "${chainA.network}" > Chain "${chainB.network}" peer is set`
  );
}

main()
  .then(() => {
    console.log("Done");
  })
  .catch(console.error);
