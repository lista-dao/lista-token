import { deployDirect, deployProxy } from "../tasks";
import hre from "hardhat";

const lisUSD = "0x785b5d1Bde70bD6042877cA08E4c73e0a40071af";
const usdt = "0xFFfF87f31d70Fb17BEEb284459C7dC4cf68EEB45";


// PancakeStableSwapLP deployed to: 0x7B9eF7b3a0A50E83dD3065595D70f456410d3463
async function main() {
  // 1. Deploy mock LP token
  const lpTokenAddr = await deployDirect(hre, "PancakeStableSwapLP");

  // 2. Deploy mock stableswap
  const stableSwapAddr = await deployProxy(hre, "MockPancakeStableSwapTwoPool", coins, A, fee, adminFee, owner, lpToken);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
