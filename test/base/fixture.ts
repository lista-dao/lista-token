import { ethers, config } from "hardhat";
import { readFileSync } from "fs";
import { sync } from "glob";
import type { MockContract } from "@ethereum-waffle/mock-contract";
import { deployMockContract as _deployMockContract } from "@ethereum-waffle/mock-contract";

const readContractAbi = (contractName: string) => {
  const files = sync(
    `${config.paths.artifacts}/contracts/**/${contractName}.sol/${contractName}.json`,
    {}
  );
  if (files.length === 0) {
    throw new Error("No files found!");
  }
  if (files.length > 1) {
    throw new Error("Multiple files found!");
  }
  return JSON.parse(readFileSync(files[0]).toString()).abi;
};

export async function deployFixture() {
  const deployMockContract = async (
    contractName: string,
    options?: { address: string; override?: boolean }
  ) => {
    const [deployer] = await ethers.getSigners();
    // @ts-ignore
    deployer.provider._hardhatNetwork = true;
    return _deployMockContract<MockContract>(
      deployer,
      readContractAbi(contractName),
      options
    );
  };

  // Bind a reference to a function that can deploy a contract on the local network.
  const deployContract = async (contractName: string, args: any[] = []) => {
    const artifacts = await ethers.getContractFactory(contractName);
    return artifacts.deploy(...args);
  };

  return { deployContract, deployMockContract };
}

export async function accountFixture() {
  // Bind a reference to the deployer address and an array of other addresses to `this`.
  const [deployer, ...addrs] = await ethers.getSigners();

  return { deployer, addrs };
}
