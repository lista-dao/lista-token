import hre, { ethers } from "hardhat";
import chains from "./oftChains.json";

/**
 * BSC Testnet: 40102 | Sepolia: 40161 | opBNB Testnet: 40202
 */
const from = 40102;

/**
 * RateLimitConfig
 * uint32 dstEid;
 * uint256 limit;
 * uint256 window(in seconds)
 */
const rateLimitConfigs = [
  [40161, ethers.utils.parseEther("500"), 60], // can't send more than 500 OFT in 1 minute
];

async function main() {
  const network = hre.network.name;
  console.log("Source Network: ", network);
  const chain = getChainByEid(from);
  const Contract = await ethers.getContractFactory(chain.contract);
  const contract = Contract.attach(chain.oft);
  // set rate limits
  const tx = await contract.setRateLimits(rateLimitConfigs);
  console.log("tx hash: ", tx.hash);
  await tx.wait(3);
  console.log(`Rate Limit is set for OFT at chain ${chain.network}`);
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
