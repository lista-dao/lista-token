"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.impersonateAccount = void 0;
const hardhat_1 = require("hardhat");
/**
 * Create a test account
 * @param {string} address
 * @param {string} balance
 * @return {ethers.JsonRpcSigner}
 */
async function impersonateAccount(address, balance = "0x0") {
  await hardhat_1.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
  await hardhat_1.network.provider.send("hardhat_setBalance", [
    address,
    balance,
  ]);
  return await hardhat_1.ethers.getSigner(address);
}
exports.impersonateAccount = impersonateAccount;
