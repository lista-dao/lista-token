import { ethers, network } from "hardhat";
import { MerkleTree } from "merkletreejs";

function toWei(eth: string) {
  return ethers.utils.parseEther(eth).toString();
}

function leafHashPacked(address: string, amount: string) {
  return ethers.utils.solidityKeccak256(
    ["address", "uint256"],
    [address, amount]
  );
}

function leafHash(account: string, weight: string, week: number) {
  const chainId = network.config.chainId;
  const encoded = ethers.utils.defaultAbiCoder.encode([ "uint256", "address", "uint256", "uint16"], [chainId, account, weight, week]);
  return ethers.utils.keccak256(encoded);
}

function readFromJsonFile(fileName: string) {
  const fs = require("fs");
  const data = fs.readFileSync(fileName, "utf8");
  return JSON.parse(data);
}

async function demoAirdrop() {
  const users = readFromJsonFile("./scripts/airdrop.json")["users"];
  const leaves = [];

  for (const user of users) {
    console.log(user);
    leaves.push(leafHashPacked(user["address"], toWei(user["amount"])));
  }
  const tree = new MerkleTree(leaves, ethers.utils.keccak256, {
    sortPairs: true,
  });
  console.log("Print tree: ", tree.toString());

  const root = tree.getRoot().toString("hex");
  const leaf = leafHashPacked(users[1].address, toWei("10001")); // user2's leaf
  const proof = tree.getProof(leaf); // user2's proof
  const leaf5 = leafHashPacked(users[4].address, toWei("1.1111111111111111")); // user5's leaf
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

async function main() {
  const users = readFromJsonFile("./scripts/demo/slisBnbWeight.json")["users"];
  const leaves = [];
  for (const user of users) {
    console.log(user);
    leaves.push(leafHash(user["account"], user["weight"], user["week"]));
  }
  const tree = new MerkleTree(leaves, ethers.utils.keccak256, {
    sortPairs: true,
  });
  console.log("Print tree: ", tree.toString());
  const root = tree.getRoot().toString("hex");
  const leaf = leafHash(users[1].account, users[1].weight, users[1].week); // user2's leaf
  const proof = tree.getProof(leaf); // user2's proof
  console.log(
    "Print proof of user2: ",
    proof.map((p) => "0x" + p.data.toString("hex"))
  );
  console.log("User2 should be able to claim:", tree.verify(proof, leaf, root)); // true

  const leaf5 = leafHash(users[4].account, users[4].weight, users[4].week); // user5's leaf
  const proof5 = tree.getProof(leaf5); // user5's proof
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
