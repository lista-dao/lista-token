import { ethers } from "hardhat";

const TOKEN = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46";
const ROOT = "0xe12f80c861a5ffa2756ee8fa6238c51fb5bd5114675d2cb580a08e64c0a642cf";
const RECLAIM_DELAY = 0;
const START_TIME = 1737446400; // Tue Jan 21 2025 08:00:00 GMT+0000
const END_TIME = 1755763200; // Thu Aug 21 2025 08:00:00 GMT+0000

async function main() {
  const MerkleVerifier = await ethers.getContractFactory("MerkleVerifier");
  const merkleVerifier = await MerkleVerifier.deploy();
  await merkleVerifier.waitForDeployment();
  console.log("MerkleVerifier deployed to:", merkleVerifier.target);

  const ListaAirdrop = await ethers.getContractFactory("ListaAirdrop", {
    libraries: {
      MerkleVerifier: merkleVerifier.target,
    },
  });
  const listaAirdrop = await ListaAirdrop.deploy(
    TOKEN, // token
    ROOT, // root
    RECLAIM_DELAY, // reclaimDelay
    START_TIME, // startTime
    END_TIME // endTime
  );
  await listaAirdrop.waitForDeployment();

  console.log("ListaAirdrop deployed to:", listaAirdrop.target);

  await run("verify:verify", {
    address: listaAirdrop.target,
    constructorArguments: [
      TOKEN, // token
      ROOT, // root
      RECLAIM_DELAY, // reclaimDelay
      START_TIME, // startTime
      END_TIME // endTime
    ],
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
