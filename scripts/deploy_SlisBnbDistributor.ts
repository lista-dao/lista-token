import hre from "hardhat";

const VAULT = "0xCfeb269242cf988b61833910E7aaC56554F09f7b";
const EXPIRE_DELAY = 100000000;
const ADMIN = "0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06";

async function main() {
  const MerkleVerifier = await hre.ethers.getContractFactory("MerkleVerifier");
  const merkleVerifier = await MerkleVerifier.deploy();
  await merkleVerifier.deployed();
  console.log("MerkleVerifier deployed to: ", merkleVerifier.address);

  const SlisBnbDistributor = await hre.ethers.getContractFactory("SlisBnbDistributor", {
    libraries: {
      MerkleVerifier: merkleVerifier.address,
    },
  });

  const slisBnbDistributor = await hre.upgrades.deployProxy(SlisBnbDistributor, [VAULT, ADMIN, EXPIRE_DELAY],
    {
      unsafeAllow: ["external-library-linking"]
    });
  await slisBnbDistributor.deployed();

  console.log("SlisBnbDistributor deployed to: ", slisBnbDistributor.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
