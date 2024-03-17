import { ethers, network } from "hardhat";

/**
 * Create a test account
 * @param {string} address
 * @param {string} balance
 * @return {ethers.JsonRpcSigner}
 */
export async function impersonateAccount(address: string, balance = "0x0") {
  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });

  await network.provider.send("hardhat_setBalance", [address, balance]);

  return await ethers.getSigner(address);
}
