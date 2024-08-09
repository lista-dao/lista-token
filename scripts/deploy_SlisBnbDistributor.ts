import hre from "hardhat";

const VAULT = "0x5C25A9FC1CFfda5D7E871C73929Dfca85ef6c92d";
const EXPIRE_DELAY = 100000000;
const ADMIN = "0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06";

async function main() {    
  const MerkleVerifier = await hre.ethers.getContractFactory("MerkleVerifier");
  const merkleVerifier = await MerkleVerifier.deploy();
  await merkleVerifier.waitForDeployment();
  console.log("MerkleVerifier deployed to: ", merkleVerifier.target);

    const SlisBnbDistributor = await hre.ethers.getContractFactory("SlisBnbDistributor", {
  libraries: {
      MerkleVerifier: merkleVerifier.target,
  },
    });
    
    const slisBnbDistributor = await hre.upgrades.deployProxy(SlisBnbDistributor, [VAULT, ADMIN, EXPIRE_DELAY],
                    {
                  unsafeAllow: ["external-library-linking"]
    });
    await slisBnbDistributor.waitForDeployment();
    
    console.log("SlisBnbDistributor deployed to: ", slisBnbDistributor.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });