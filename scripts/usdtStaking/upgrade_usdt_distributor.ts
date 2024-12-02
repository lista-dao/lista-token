import hre from "hardhat";

const stableSwap = "0xeE7c95A9e4206a1daBFb15C4F471c6D5f5e8863F";
const stableSwapInfo = "0x0A548d59D04096Bc01206D58C3D63c478e1e06dB";
const v2wrapper = "0x0921d42D5B7511b586A6A522fFd041394E4879e8";
const constructorArguments = [stableSwap, stableSwapInfo, v2wrapper];

const proxy = "0x65eb3ec2507eE7bB9F1324010E5AAcd04eedf5EE";

async function main() {
  const Contract = await hre.ethers.getContractFactory("USDTLpListaDistributor");

  console.log("Upgrade proxy USDTLpListaDistributor");
  const contract = await hre.upgrades.upgradeProxy(proxy, Contract, {
    unsafeAllow: ["constructor"],
    constructorArgs: constructorArguments,
  });

  await contract.waitForDeployment();

  const proxyAddress = await contract.getAddress();

  const contractImplAddress =
    await hre.upgrades.erc1967.getImplementationAddress(proxyAddress);

  console.log("Upgraded USDTLpListaDistributor deployed to:", proxyAddress);
  console.log("Impl USDTLpListaDistributor deployed to:", contractImplAddress);

  try {
    await hre.run("verify:verify", {
      address: contractImplAddress,
      constructorArguments: constructorArguments,
      contract: "contracts/dao/USDTLpListaDistributor.sol:USDTLpListaDistributor",
    });
    await hre.run("verify:verify", {
      address: proxyAddress,
    });
  } catch (e) {
    console.log("Error verifying contract:", e);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
