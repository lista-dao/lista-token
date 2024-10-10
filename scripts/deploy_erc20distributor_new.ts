import { deployProxy } from "./tasks";
import hre from "hardhat";

async function main() {
  // todo
  const lpToken = "0x5eBFbF56048575d37C033843F2AC038885EBB636";
  const isPancake = true;

  let staking;
  let stakeVault;
  if (isPancake) {
    staking = "0xE31f0BcE1F825A8e27f2Cc30B54af19DA2978f10";
    stakeVault = "0x62DfeC5C9518fE2e0ba483833d1BAD94ecF68153";
  } else {
    staking = "0xFA5B482882F9e025facCcE558c2F72c6c50AC719";
    stakeVault = "0xF40D0d497966fe198765877484FFf08c2D2004ad";
  }
  const listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";

  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  const address = await deployProxy(
    hre,
    "ERC20LpListaDistributor",
    deployer,
    deployer,
    listaVault,
    lpToken
  );

  const contract = await hre.ethers.getContractAt("ERC20LpListaDistributor", address);

  await contract.setStaking(staking);
  await contract.setStakeVault(stakeVault);

  console.log("deploy lp done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
