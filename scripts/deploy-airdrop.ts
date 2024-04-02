import { ethers } from "hardhat";

const TOKEN = "";
const ROOT = "";
const RECLAIM_DELAY = 0;
const START_BLOCK = 0;
const END_BLOCK = 0;

async function main() {
  //  const startBlock = (await ethers.provider.getBlockNumber()) + 5;
  //  console.log("Start block:", startBlock);

  const MerkleVerifier = await ethers.getContractFactory("MerkleVerifier");
  const merkleVerifier = await MerkleVerifier.deploy();
  await merkleVerifier.deployed();

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
