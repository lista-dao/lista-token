import { ethers } from "hardhat";
import { expect } from "chai";
import { MerkleTree } from "merkletreejs";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

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
  let user4: SignerWithAddress;
  let treasury: SignerWithAddress;
  let tree: MerkleTree;
  let root: string;
  let proof1: any[];
  let proof2: any[];
  let proof3: any[];
  let proof4: any[];
  before(async function () {
    [owner, user1, user2, user3, user4, treasury] = await ethers.getSigners();

    const leaves = [
      leafHash(user1.address, toWei("1")), // user1 node
      leafHash(user2.address, toWei("1")), // user2 node
      leafHash(user3.address, toWei("1")), // user3 node
      leafHash(user4.address, toWei("101")), // user4 node
    ];

    tree = new MerkleTree(leaves, ethers.utils.keccak256, {
      sortPairs: true,
    });

    console.log(tree.toString());

    root = tree.getRoot().toString("hex");
    const leaf1 = leafHash(user1.address, toWei("1")); // user1
    const leaf2 = leafHash(user2.address, toWei("1")); // user2
    const leaf3 = leafHash(user3.address, toWei("1")); // user3
    const leaf4 = leafHash(user4.address, toWei("101")); // user4
    proof1 = tree.getProof(leaf1);
    proof2 = tree.getProof(leaf2);
    proof3 = tree.getProof(leaf3);
    proof4 = tree.getProof(leaf4);
    expect(tree.verify(proof1, leaf1, root)).to.be.true;
    expect(tree.verify(proof2, leaf2, root)).to.be.true;
    expect(tree.verify(proof3, leaf3, root)).to.be.true;
    expect(tree.verify(proof4, leaf4, root)).to.be.true;

    // contract deploy treasury
    listaToken = await ethers.deployContract("ListaToken", [treasury.address]);
    await listaToken.deployed();

    const MerkleVerifier = await ethers.getContractFactory("MerkleVerifier");
    merkleVerifier = await MerkleVerifier.deploy();
    await merkleVerifier.deployed();

    const reclaimDelay = 0;
    const startBlock = (await ethers.provider.getBlockNumber()) + 20;
    const endBlock = startBlock + 200;
    const ListaAirdrop = await ethers.getContractFactory("ListaAirdrop", {
      libraries: {
        MerkleVerifier: merkleVerifier.address,
      },
    });
    const fakeRoot = ethers.utils.formatBytes32String("");
    listaAirdrop = await ListaAirdrop.deploy(
      listaToken.address,
      fakeRoot, // bytes32
      reclaimDelay,
      startBlock,
      endBlock
    );
    await listaAirdrop.deployed();

    await listaToken
      .connect(treasury)
      .transfer(listaAirdrop.address, toWei("10"));

    await listaAirdrop.setStartBlock(startBlock + 1);
    expect(await listaAirdrop.startBlock()).to.equals(startBlock + 1);
  });

  it("should work", async function () {
    await listaAirdrop.setMerkleRoot("0x" + root);
    expect(await listaAirdrop.merkleRoot()).to.equals("0x" + root);

    // shoule revert if not started
    await expect(
      listaAirdrop.claim(
        user1.address,
        toWei("1"),
        proof1.map((p) => "0x" + p.data.toString("hex"))
      )
    ).to.be.revertedWith("Airdrop not started or has ended");

    // advance to start block
    await mine(20);

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

  it("shoule revert if the user has already claimed or has ended", async function () {
    await expect(
      listaAirdrop.claim(
        user1.address,
        toWei("1"),
        proof1.map((p) => "0x" + p.data.toString("hex"))
      )
    ).to.be.revertedWith("Airdrop already claimed");

    // advance to end block
    await mine(30000);

    // user4 can't claim
    await expect(
      listaAirdrop.claim(
        user4.address,
        toWei("101"),
        proof4.map((p) => "0x" + p.data.toString("hex"))
      )
    ).to.be.revertedWith("Airdrop not started or has ended");
  });

  it("owner should be able to reclaim", async function () {
    const balanceBefore = await listaToken.balanceOf(owner.address);
    await listaAirdrop.connect(owner).reclaim(toWei("1"));
    expect(await listaToken.balanceOf(owner.address)).to.equals(
      balanceBefore.add(toWei("1"))
    );
  });

  it("owner should not be able to set merkle root once claim started", async function () {
    const newRoot = ethers.utils.formatBytes32String("");
    await expect(listaAirdrop.setMerkleRoot(newRoot)).to.be.revertedWith(
      "Cannot change merkle root after airdrop has started"
    );
  });

  it("owner should be not able to set start block after ended", async function () {
    const startBlock = await listaAirdrop.startBlock();
    await expect(listaAirdrop.setStartBlock(startBlock)).to.be.revertedWith(
      "Start block already set"
    );
    const newStartBlock = (await ethers.provider.getBlockNumber()) + 1;
    await expect(listaAirdrop.setStartBlock(newStartBlock)).to.be.revertedWith(
      "Invalid start block"
    );
  });

  it("owner should be able to set end block", async function () {
    const endBlock = await listaAirdrop.endBlock();
    await expect(listaAirdrop.setEndBlock(endBlock)).to.be.revertedWith(
      "End block already set"
    );
    const newEndBlock = (await ethers.provider.getBlockNumber()) + 200;
    await listaAirdrop.setEndBlock(newEndBlock);

    expect(await listaAirdrop.endBlock()).to.equals(newEndBlock);
  });
});
