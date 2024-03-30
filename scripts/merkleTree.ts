import { ethers } from "hardhat";
import { MerkleTree } from "merkletreejs";

function toWei(eth: string) {
  return ethers.utils.parseEther(eth).toString();
}

function leafHash(address: string, amount: string) {
  return ethers.utils.solidityKeccak256(
    ["address", "uint256"],
    [address, amount]
  );
}

function readFromJsonFile(fileName: string) {
  const fs = require("fs");
  const data = fs.readFileSync(fileName, "utf8");
  return JSON.parse(data);
}

async function main() {
  const users = readFromJsonFile("./scripts/airdrop.json")["users"];
  const leaves = [];

  for (const user of users) {
    console.log(user);
    leaves.push(leafHash(user["address"], toWei(user["amount"])));
  }
  const tree = new MerkleTree(leaves, ethers.utils.keccak256, {
    sortPairs: true,
  });
  console.log("Print tree: ", tree.toString());

  const root = tree.getRoot().toString("hex");
  const leaf = leafHash(users[1].address, toWei("10001")); // user2's leaf
  const proof = tree.getProof(leaf); // user2's proof
  const leaf5 = leafHash(users[4].address, toWei("1.1111111111111111")); // user5's leaf
  const proof5 = tree.getProof(leaf5); // user2's proof

  console.log(
    "Print proof of user2: ",
    proof.map((p) => "0x" + p.data.toString("hex"))
  );
  console.log("User2 should be able to claim:", tree.verify(proof, leaf, root)); // true

  console.log(
    "Print proof of user5: ",
    proof5.map((p) => "0x" + p.data.toString("hex"))
  );
  console.log(
    "User5 should be able to claim:",
    tree.verify(proof5, leaf5, root)
  ); // true
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
