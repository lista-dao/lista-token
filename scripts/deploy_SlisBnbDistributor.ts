import hre from "hardhat";

const EXPIRE_DELAY = 100000000;

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;
  let listaVault;
  if (hre.network.name === "bsc") {
    // todo
    listaVault = "";
  } else if (hre.network.name === "bscTestnet") {
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
  }
  const MerkleVerifier = await hre.ethers.getContractFactory("MerkleVerifier");
  const merkleVerifier = await MerkleVerifier.deploy();
  await merkleVerifier.waitForDeployment();
  const merkleVerifierAddress = await merkleVerifier.getAddress();
  console.log("MerkleVerifier deployed to: ", merkleVerifierAddress);

  const SlisBnbDistributor = await hre.ethers.getContractFactory("SlisBnbDistributor", {
    libraries: {
      MerkleVerifier: merkleVerifierAddress,
    },
  });

  const slisBnbDistributor = await hre.upgrades.deployProxy(SlisBnbDistributor, [listaVault, deployer, EXPIRE_DELAY],
    {
      unsafeAllow: ["external-library-linking"]
    });

  await slisBnbDistributor.waitForDeployment();
  const address = await slisBnbDistributor.getAddress();


  const contract = await hre.ethers.getContractAt("ListaVault", listaVault);

  await contract.registerDistributor(address);
  console.log("SlisBnbDistributor deployed to: ", address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
