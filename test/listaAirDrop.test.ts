import { ethers } from "hardhat";
import { expect } from "chai";
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

describe("ListaAirdrop", function () {
  let listaAirdrop: Contract;
  let listaToken: Contract;
  let merkleVerifier: Contract;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;
  let treasury: SignerWithAddress;
  let tree: MerkleTree;
  let root: string;
  let proof1: any[];
  let proof2: any[];
  let proof3: any[];
  before(async function () {
    [owner, user1, user2, user3, treasury] = await ethers.getSigners();

    const leaves = [
      leafHash(user1.address, toWei("1")), // user1 node
      leafHash(user2.address, toWei("1")), // user2 node
      leafHash(user3.address, toWei("1")), // user3 node
    ];

    tree = new MerkleTree(leaves, ethers.utils.keccak256);

    //    console.log(tree.toString());

    root = tree.getRoot().toString("hex");
    const leaf1 = leafHash(user1.address, toWei("1")); // user1
    const leaf2 = leafHash(user2.address, toWei("1")); // user2
    const leaf3 = leafHash(user3.address, toWei("1")); // user3
    proof1 = tree.getProof(leaf1);
    proof2 = tree.getProof(leaf2);
    proof3 = tree.getProof(leaf3);
    expect(tree.verify(proof1, leaf1, root)).to.be.true;
    expect(tree.verify(proof2, leaf2, root)).to.be.true;
    expect(tree.verify(proof3, leaf3, root)).to.be.true;

    // contract deploy treasury
    listaToken = await ethers.deployContract("ListaToken", [treasury.address]);
    await listaToken.deployed();

    const MerkleVerifier = await ethers.getContractFactory("MerkleVerifier");
    merkleVerifier = await MerkleVerifier.deploy();
    await merkleVerifier.deployed();

    const reclaimDelay = 0;
    const startBlock = (await ethers.provider.getBlockNumber()) + 1;
    const ListaAirdrop = await ethers.getContractFactory("ListaAirdrop", {
      libraries: {
        MerkleVerifier: merkleVerifier.address,
      },
    });
    listaAirdrop = await ListaAirdrop.deploy(
      listaToken.address,
      "0x" + root, // bytes32
      reclaimDelay,
      startBlock
    );
    await listaAirdrop.deployed();

    await listaToken
      .connect(treasury)
      .transfer(listaAirdrop.address, toWei("10"));
  });

  it("should work", async function () {
    // shoule revert if incorrect proof provided
    await expect(
      listaAirdrop.claim(
        user1.address,
        toWei("1"),
        proof2.map((p) => "0x" + p.data.toString("hex"))
      )
    ).to.be.revertedWith("InvalidProof()");

    // user1 can claim
    await expect(
      listaAirdrop.claim(
        user1.address,
        toWei("1"),
        proof1.map((p) => "0x" + p.data.toString("hex"))
      )
    )
      .to.emit(listaAirdrop, "Claimed")
      .withArgs(user1.address, toWei("1"));

    // user2 can claim
    await expect(
      listaAirdrop.claim(
        user2.address,
        toWei("1"),
        proof2.map((p) => "0x" + p.data.toString("hex"))
      )
    )
      .to.emit(listaAirdrop, "Claimed")
      .withArgs(user2.address, toWei("1"));

    // user3 can claim
    await expect(
      listaAirdrop.claim(
        user3.address,
        toWei("1"),
        proof3.map((p) => "0x" + p.data.toString("hex"))
      )
    )
      .to.emit(listaAirdrop, "Claimed")
      .withArgs(user3.address, toWei("1"));
  });

  it("shoule revert if the user has already claimed", async function () {
    await expect(
      listaAirdrop.claim(
        user1.address,
        toWei("1"),
        proof1.map((p) => "0x" + p.data.toString("hex"))
      )
    ).to.be.revertedWith("Airdrop already claimed");
  });

  it("owner should be able to reclaim", async function () {
    const balanceBefore = await listaToken.balanceOf(owner.address);
    await listaAirdrop.connect(owner).reclaim(toWei("1"));
    expect(await listaToken.balanceOf(owner.address)).to.equals(
      balanceBefore.add(toWei("1"))
    );
  });

  it("owner should be able to set merkle root", async function () {
    const newRoot = ethers.utils.formatBytes32String("");
    await listaAirdrop.setMerkleRoot(newRoot);

    expect(await listaAirdrop.merkleRoot()).to.equals(newRoot);
  });

  it("owner should be able to set start block", async function () {
    const newStartBlock = (await ethers.provider.getBlockNumber()) + 1;
    await listaAirdrop.setStartBlock(newStartBlock);

    expect(await listaAirdrop.startBlock()).to.equals(newStartBlock);
  });
});
