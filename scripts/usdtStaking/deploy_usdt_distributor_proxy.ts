import hre from "hardhat";

const admin = "0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06";
const listaVault = "0x0fD548f448AAB6dE7489F8FD1a4be1efca009f1C";
const stakingVault = "0x4EED5fa7344d7B40c548d21f151A89bBE750F59c";
const stableSwap = "0xeE7c95A9e4206a1daBFb15C4F471c6D5f5e8863F";
const stableSwapInfo = "0x0A548d59D04096Bc01206D58C3D63c478e1e06dB";
const v2wrapper = "0x0921d42D5B7511b586A6A522fFd041394E4879e8";

const constructorArguments = [stableSwap, stableSwapInfo, v2wrapper];

// Proxy USDTLpListaDistributor deployed to: 0x0502142b0B7Ff90fa6B6bab739A5417E027a4Df7
// Impl USDTLpListaDistributor deployed to: 0xAff595E4A062508a99fF5BB10cBEEB446C4Db5d4
async function main() {
  const Contract = await hre.ethers.getContractFactory("USDTLpListaDistributor");

  console.log("Deploying proxy USDTLpListaDistributor");
  const contract = await hre.upgrades.deployProxy(Contract, [admin, admin, admin, listaVault, stakingVault], {
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
