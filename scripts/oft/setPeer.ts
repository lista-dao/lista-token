import hre, { ethers } from "hardhat";
import chains from "./oftChains.json";

/**
 * BSC Testnet: 40102 | Sepolia: 40161 | opBNB Testnet: 40202
 */
const from = 40161;
const to = 40202;

async function main() {
  const network = hre.network.name;
  console.log("Source Network: ", network);
  const chainA = getChainByEid(from);
  const chainB = getChainByEid(to);
  const Contract = await ethers.getContractFactory(chainA.contract);
  const contract = Contract.attach(chainA.oft);
  // set peer
  const tx = await contract.setPeer(
    chainB.eid,
    ethers.utils.arrayify(ethers.utils.hexZeroPad(chainB.oft, 32))
  );
  console.log("tx hash: ", tx.hash);
  await tx.wait(3);
  console.log(
    `Chain "${chainA.network}" > Chain "${chainB.network}" peer is set`
  );
}

function getChainByEid(eid: number) {
  const c = chains.filter((c) => (c.eid as number) === eid)[0];
  if (!c) throw new Error("Chain not found");
  return c;
}

main()
  .then(() => {
    console.log("Done");
  })
  .catch(console.error);
