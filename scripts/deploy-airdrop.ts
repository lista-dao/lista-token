import { ethers } from "hardhat";

const TOKEN = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46";
const ROOT = "0xe12f80c861a5ffa2756ee8fa6238c51fb5bd5114675d2cb580a08e64c0a642cf";
const RECLAIM_DELAY = 0;
const START_BLOCK = 39773281;
const END_BLOCK = 40609575;

async function main() {
  //  const startBlock = (await ethers.provider.getBlockNumber()) + 5;
  //  console.log("Start block:", startBlock);

  const MerkleVerifier = await ethers.getContractFactory("MerkleVerifier");
  const merkleVerifier = await MerkleVerifier.deploy();
  await merkleVerifier.deployed();
  console.log("MerkleVerifier deployed to:", merkleVerifier.address);

  const ListaAirdrop = await ethers.getContractFactory("ListaAirdrop", {
    libraries: {
      MerkleVerifier: merkleVerifier.address,
    },
  });
  const listaAirdrop = await ListaAirdrop.deploy(
    TOKEN, // token
    ROOT, // root
    RECLAIM_DELAY, // reclaimDelay
    START_BLOCK, // startBlock
    END_BLOCK // endBlock
  );
  await listaAirdrop.deployed();

  console.log("ListaAirdrop deployed to:", listaAirdrop.address);

  await run("verify:verify", {
    address: listaAirdrop.address,
    constructorArguments: [
      TOKEN, // token
      ROOT, // root
      RECLAIM_DELAY, // reclaimDelay
      START_BLOCK, // startBlock
      END_BLOCK, // endBlock
    ],
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
