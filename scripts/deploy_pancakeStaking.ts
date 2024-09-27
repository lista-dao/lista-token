import { deployDirect, deployProxy } from "./tasks";
import hre from "hardhat";
import Promise from "bluebird";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  // todo
  const pancakeVault = "";

  const address = await deployProxy(
    hre,
    "PancakeStaking",
    deployer,
    pancakeVault
  );

  const pancakeStakingContract = await hre.ethers.getContractAt(
    "PancakeStaking",
    address
  );
  const pancakeVaultContract = await hre.ethers.getContractAt(
    "StakingVault",
    pancakeVault
  );

  await pancakeVaultContract.setStaking(address);

  await Promise.delay(3000);

  const pools = [
    // Pancake stable lisUSD/USDT
    {
      lpToken: "0xB2Aa63f363196caba3154D4187949283F085a488",
      pool: "0xd069a9E50E4ad04592cb00826d312D9f879eBb02",
      distributor: "0xe8f4644637f127aFf11F9492F41269eB5e8b8dD2",
    },
  ];

  for (const pool of pools) {
    await pancakeStakingContract.registerPool(
      pool.lpToken,
      pool.pool,
      pool.distributor
    );
  }
  console.log("deploy and setup contract done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
