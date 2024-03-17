"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.accountFixture = exports.deployFixture = void 0;
const hardhat_1 = require("hardhat");
const fs_1 = require("fs");
const glob_1 = require("glob");
const mock_contract_1 = require("@ethereum-waffle/mock-contract");
const readContractAbi = (contractName) => {
  const files = (0, glob_1.sync)(
    `${hardhat_1.config.paths.artifacts}/contracts/**/${contractName}.sol/${contractName}.json`,
    {}
  );
  if (files.length === 0) {
    throw new Error("No files found!");
  }
  if (files.length > 1) {
    throw new Error("Multiple files found!");
  }
  return JSON.parse((0, fs_1.readFileSync)(files[0]).toString()).abi;
};
async function deployFixture() {
  const deployMockContract = async (contractName, options) => {
    const [deployer] = await hardhat_1.ethers.getSigners();
    // @ts-ignore
    deployer.provider._hardhatNetwork = true;
    return (0, mock_contract_1.deployMockContract)(
      deployer,
      readContractAbi(contractName),
      options
    );
  };
  // Bind a reference to a function that can deploy a contract on the local network.
  const deployContract = async (contractName, args = []) => {
    const artifacts = await hardhat_1.ethers.getContractFactory(contractName);
    return artifacts.deploy(...args);
  };
  return { deployContract, deployMockContract };
}
exports.deployFixture = deployFixture;
async function accountFixture() {
  // Bind a reference to the deployer address and an array of other addresses to `this`.
  const [deployer, ...addrs] = await hardhat_1.ethers.getSigners();
  return { deployer, addrs };
}
exports.accountFixture = accountFixture;
