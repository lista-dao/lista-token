import { ethers } from "hardhat";
import hre from "hardhat";

let token = "";
const ROOT = "0x93f599435d274a0e423df9717e4d19c1595513874cedcc6ab8cb8b6d7afae9d5";
const RECLAIM_DELAY = 0;
const START_TIME = 1737446400; // Tue Jan 21 2025 08:00:00 GMT+0000
const END_TIME = 1755763200; // Thu Aug 21 2025 08:00:00 GMT+0000

async function main() {
  const MerkleVerifier = await ethers.getContractFactory("MerkleVerifier");
  const merkleVerifier = await MerkleVerifier.deploy();
  await merkleVerifier.waitForDeployment();
  console.log("MerkleVerifier deployed to:", merkleVerifier.target);

  if (hre.network.name === "bsc") {
    token = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46"; // LISTA
  } else if (hre.network.name === "bscTestnet") {
    token = "0x90b94D605E069569Adf33C0e73E26a83637c94B1";
  }
  const ListaAirdrop = await ethers.getContractFactory("ListaAirdrop", {
    libraries: {
      MerkleVerifier: merkleVerifier.target,
    },
  });
  const listaAirdrop = await ListaAirdrop.deploy(
    token, // LISTA token
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
      token, // token
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
