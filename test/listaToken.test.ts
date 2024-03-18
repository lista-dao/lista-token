import { expect } from "chai";
import { BigNumberish, Contract } from "ethers";
import { ethers } from "hardhat";
import { loadFixture } from "ethereum-waffle";

import { accountFixture } from "./base/fixture";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

/**
 * get signature
 */
async function getSignature(
  address: string,
  name: string,
  version: string,
  chainId: number,
  owner: string,
  spender: string,
  value: BigNumberish,
  nonce: BigNumberish,
  deadline: BigNumberish,
  signer: SignerWithAddress
) {
  // set the domain parameters
  const domain = {
    name,
    version,
    chainId,
    verifyingContract: address,
  };

  // set the Permit type parameters
  const types = {
    Permit: [
      {
        name: "owner",
        type: "address",
      },
      {
        name: "spender",
        type: "address",
      },
      {
        name: "value",
        type: "uint256",
      },
      {
        name: "nonce",
        type: "uint256",
      },
      {
        name: "deadline",
        type: "uint256",
      },
    ],
  };

  // set the Permit type values
  const values = {
    owner,
    spender,
    value,
    nonce,
    deadline,
  };

  const signature = await signer._signTypedData(domain, types, values);

  // split the signature into its components
  return ethers.utils.splitSignature(signature);
}

describe("ListaToken", function () {
  let listaToken: Contract;
  let deployer: SignerWithAddress;
  let owner: SignerWithAddress;
  let spender1: SignerWithAddress;
  let spender2: SignerWithAddress;

  let name: string;
  let chainId: number;
  let version: string;
  const totalSupply = ethers.utils.parseEther(String(10 ** 9));

  before(async function () {
    const accounts = await loadFixture(accountFixture);
    deployer = accounts.deployer;
    [owner, spender1, spender2] = accounts.addrs;

    const factory = await ethers.getContractFactory("ListaToken");
    listaToken = await factory.deploy(owner.getAddress());
    await listaToken.deployed();

    // init properties
    name = await listaToken.name();
    chainId = ethers.provider.network.chainId;
    version = await listaToken.EIP712_VERSION();

    // the total supply is 1B
    expect(await listaToken.totalSupply()).to.equals(totalSupply);

    // the owner has 1B
    expect(await listaToken.balanceOf(owner.address)).to.equals(totalSupply);

    // name is "Lista DAO"
    expect(name).to.equals("Lista DAO");

    // symbol is "LISTA"
    expect(await listaToken.symbol()).to.equals("LISTA");
  });

  // test erc20 functions
  describe("ERC20", async () => {
    it("Transfer tokens should be ok", async () => {
      const balanceBeforeOfOwner = await listaToken.balanceOf(owner.address);
      const balanceBeforeOfSpender = await listaToken.balanceOf(
        spender1.address
      );
      // cannot transfer without enough balance
      await expect(
        listaToken
          .connect(deployer)
          .transfer(spender1.address, totalSupply.add(1))
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
      // cannot transfer more than the balance
      await expect(
        listaToken.connect(owner).transfer(spender1.address, totalSupply.add(1))
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
      // transfer 10 tokens to spender1 from owner
      const amount = ethers.utils.parseEther("10");
      await expect(listaToken.connect(owner).transfer(spender1.address, amount))
        .to.emit(listaToken, "Transfer")
        .withArgs(owner.address, spender1.address, amount);
      // the spender should have 10 tokens
      expect(await listaToken.balanceOf(spender1.address)).to.equals(
        balanceBeforeOfSpender.add(amount)
      );
      // the owner should have 1B - amount tokens
      expect(await listaToken.balanceOf(owner.address)).to.equals(
        balanceBeforeOfOwner.sub(amount)
      );
    });

    // can approve and transferFrom
    it("Approve and transferFrom should be ok", async () => {
      const amount = ethers.utils.parseEther("10");
      // transfer 10 tokens to spender2 from owner
      await listaToken.connect(owner).transfer(spender2.address, amount);
      // approve spender1 to transfer 5 tokens from sender2
      const approveAmount = ethers.utils.parseEther("5");
      await expect(
        listaToken.connect(spender2).approve(spender1.address, approveAmount)
      )
        .to.be.emit(listaToken, "Approval")
        .withArgs(spender2.address, spender1.address, approveAmount);
      // check the allowance
      expect(
        await listaToken.allowance(spender2.address, spender1.address)
      ).to.equals(approveAmount);
      const balanceBeforeOfOwner = await listaToken.balanceOf(owner.address);
      const balanceBeforeOfSpender2 = await listaToken.balanceOf(
        spender2.address
      );
      // cannot transfer more than the allowance
      await expect(
        listaToken
          .connect(spender1)
          .transferFrom(spender2.address, owner.address, approveAmount.add(1))
      ).to.be.revertedWith("ERC20: insufficient allowance");

      // transfer approved amount tokens from spender2 to owner
      await expect(
        listaToken
          .connect(spender1)
          .transferFrom(spender2.address, owner.address, approveAmount)
      )
        .to.be.emit(listaToken, "Transfer")
        .withArgs(spender2.address, owner.address, approveAmount);
      expect(await listaToken.balanceOf(owner.address)).to.equals(
        balanceBeforeOfOwner.add(approveAmount)
      );
      expect(await listaToken.balanceOf(spender2.address)).to.equals(
        balanceBeforeOfSpender2.sub(approveAmount)
      );
    });
  });

  describe("permit(address, address, uint256, uint256, uint256)", async () => {
    it("Should revert if deadline is in the past", async () => {
      const approve = {
        owner: await owner.getAddress(),
        spender: await spender1.getAddress(),
        value: ethers.utils.parseEther("10"),
      };
      // get latest block timestamp
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp - 1;
      const nonce = await listaToken.nonces(owner.getAddress());
      // signature
      const { v, r, s } = await getSignature(
        listaToken.address,
        name,
        version,
        chainId,
        owner.address,
        spender1.address,
        approve.value,
        nonce,
        deadline,
        owner
      );
      await expect(
        listaToken.permit(
          approve.owner,
          approve.spender,
          approve.value,
          deadline,
          v,
          r,
          s
        )
      ).to.be.revertedWith("ERC20Permit: expired deadline");
    });

    it("Should revert if the recoveredAddress is not the owner", async () => {
      const approve = {
        owner: await owner.getAddress(),
        spender: await spender1.getAddress(),
        value: ethers.utils.parseEther("10"),
      };
      // get latest block timestamp
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 60;
      const nonce = await listaToken.nonces(owner.getAddress());
      // signature
      const { v, r, s } = await getSignature(
        listaToken.address,
        name,
        version,
        chainId,
        owner.address,
        approve.spender,
        approve.value,
        nonce,
        deadline,
        owner
      );
      await expect(
        listaToken.permit(
          deployer.address,
          approve.spender,
          approve.value,
          deadline,
          v,
          r,
          s
        )
      ).to.be.revertedWith("ERC20Permit: invalid signature");
      await expect(
        listaToken.permit(
          owner.address,
          spender2.address,
          approve.value,
          deadline,
          v,
          r,
          s
        )
      ).to.be.revertedWith("ERC20Permit: invalid signature");
    });

    it("Should OK", async () => {
      const approve = {
        owner: await owner.getAddress(),
        spender: await spender1.getAddress(),
        value: ethers.utils.parseEther("10"),
      };
      const beforeApproved = await listaToken.allowance(
        approve.owner,
        approve.spender
      );
      // get latest block timestamp
      const block = await ethers.provider.getBlock("latest");
      const deadline = block.timestamp + 60;
      const nonce = await listaToken.nonces(owner.getAddress());
      // signature
      const { v, r, s } = await getSignature(
        listaToken.address,
        name,
        version,
        chainId,
        owner.address,
        approve.spender,
        approve.value,
        nonce,
        deadline,
        owner
      );
      await expect(
        listaToken.permit(
          approve.owner,
          approve.spender,
          approve.value,
          deadline,
          v,
          r,
          s
        )
      )
        .to.be.emit(listaToken, "Approval")
        .withArgs(approve.owner, approve.spender, approve.value);
      // check the allowance
      expect(
        await listaToken.allowance(approve.owner, approve.spender)
      ).to.equals(approve.value.add(beforeApproved));
      // the nonce can only use once
      await expect(
        listaToken.permit(
          approve.owner,
          approve.spender,
          approve.value,
          deadline,
          v,
          r,
          s
        )
      ).to.be.revertedWith("ERC20Permit: invalid signature");
    });
  });
});
