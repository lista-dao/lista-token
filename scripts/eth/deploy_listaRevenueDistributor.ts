import { deployProxy } from "../tasks";
import hre from "hardhat";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  console.log("admin: ", deployer);

  // ETH mainnet deployment
  // Fee flow: Moolah → LendingFeeRecipient(0xd10a024602E042dcb9C19e21682c3b896c8B0d30) → ListaRevenueDistributor (this contract)
  // Revenue accumulates here, MANAGER calls emergencyWithdraw() for cross-chain bridging to BSC
  //
  // After deployment:
  // 1. Record this proxy address
  // 2. Fill it into MarketFactory deploy script (listaRevenueDistributor)
  // 3. Call LendingFeeRecipient(0xd10a024602E042dcb9C19e21682c3b896c8B0d30).setMarketFeeRecipient(this proxy address)
  const bot = '0x8d388136d578dCD791D081c6042284CED6d9B0c6'; // Manager Safe (calls emergencyWithdraw)
  const listaAddress = '0x0000000000000000000000000000000000000000'; // not relevant on ETH, set to address(0)
  const autoBuybackAddress = '0x0000000000000000000000000000000000000000'; // not used on ETH
  const revenueWalletAddress = '0x0000000000000000000000000000000000000000'; // not used on ETH
  const listaDistributeToAddress = '0x0000000000000000000000000000000000000000'; // not used on ETH
  const distributeRate = '700000000000000000'; // 70% (doesn't matter when all targets are address(0))

  await deployProxy(hre, "ListaRevenueDistributor", deployer, bot, listaAddress, autoBuybackAddress, revenueWalletAddress, listaDistributeToAddress, distributeRate);
  console.log("deployProxy done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
