import hre from "hardhat";


async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  const MerkleVerifier = await hre.ethers.getContractFactory("MerkleVerifier");
  const merkleVerifier = await MerkleVerifier.deploy();
  await merkleVerifier.waitForDeployment();
  const merkleVerifierAddress = await merkleVerifier.getAddress();
  console.log("MerkleVerifier deployed to: ", merkleVerifierAddress);

  const ClisBNBLaunchPoolDistributor = await hre.ethers.getContractFactory("ClisBNBLaunchPoolDistributor", {
    libraries: {
      MerkleVerifier: merkleVerifierAddress,
    },
  });

  const clisBNBLaunchPoolDistributorProxy = await hre.upgrades.deployProxy(ClisBNBLaunchPoolDistributor, [deployer],
    {
      unsafeAllow: ["external-library-linking"]
    });

  await clisBNBLaunchPoolDistributorProxy.waitForDeployment();
  const address = await clisBNBLaunchPoolDistributorProxy.getAddress();
  console.log("ClisBNBLaunchPoolDistributor deployed to: ", address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
