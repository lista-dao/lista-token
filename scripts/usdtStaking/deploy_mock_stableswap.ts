import { deployProxy, upgradeProxy } from "../tasks";
import hre from "hardhat";

const lisUSD = "0x785b5d1Bde70bD6042877cA08E4c73e0a40071af";
const usdt = "0xFFfF87f31d70Fb17BEEb284459C7dC4cf68EEB45";
const coins = [lisUSD, usdt];
const A = "1000";
const fee = "4000000";
const adminFee = "5000000000";
const owner = "0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06";
const lpToken = "0x7B9eF7b3a0A50E83dD3065595D70f456410d3463";

// Proxy MockPancakeStableSwapTwoPool deployed to: 0xeE7c95A9e4206a1daBFb15C4F471c6D5f5e8863F
async function main() {
  await deployProxy(hre, "MockPancakeStableSwapTwoPool", coins, A, fee, adminFee, owner, lpToken);
}

async function addLiquidity() {
  const sspool= "0xeE7c95A9e4206a1daBFb15C4F471c6D5f5e8863F";

  const Contract = await hre.ethers.getContractFactory("MockPancakeStableSwapTwoPool");
  const contract = Contract.attach(sspool);
  // set token whitelist
  const tx = await contract.add_liquidity(["100000000000000000000","100000000000000000000"],"90000000000000000000");
  console.log("tx hash: ", tx.hash);
  await tx.wait(3);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
