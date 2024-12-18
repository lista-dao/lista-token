import hre from "hardhat";

const admin = "0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253";
const manager = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";
const pauser = "0xEEfebb1546d88EA0909435DF6f615084DD3c5Bd8";
const listaVault = "0x307d13267f360f78005f476Fa913F8848F30292A";
const stakingVault = "0x62DfeC5C9518fE2e0ba483833d1BAD94ecF68153";

const stableSwap = "0xb1Da7D2C257c5700612BdE35C8d7187dc80d79f1";
const stableSwapInfo = "0x150c8AbEB487137acCC541925408e73b92F39A50";
const v2wrapper = "0xd069a9E50E4ad04592cb00826d312D9f879eBb02";

const constructorArguments = [stableSwap, stableSwapInfo, v2wrapper];

async function main() {
  const Contract = await hre.ethers.getContractFactory("USDTLpListaDistributor");

  console.log("Deploying proxy USDTLpListaDistributor");
  const contract = await hre.upgrades.deployProxy(Contract, [admin, manager, pauser, listaVault, stakingVault], {
    unsafeAllow: ["constructor"],
    constructorArgs: constructorArguments,
  });

  await contract.waitForDeployment();

  const proxyAddress = await contract.getAddress();

  const contractImplAddress =
    await hre.upgrades.erc1967.getImplementationAddress(proxyAddress);

  console.log("Proxy USDTLpListaDistributor deployed to:", proxyAddress);
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
