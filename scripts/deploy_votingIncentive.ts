import { deployProxyUUPS } from "./tasks";
import hre from "hardhat";

const admin = "0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06";
const adminVoter = "0xF45FB2567C2E081a2C866bba10d3dc543AFa2920";
const vault = "0x1D70D733401169055002FB4450942F15C2F088d4";
const emissionVoting = "0x6B7B87F92354bEC0eC20Db0CB328e186cda950dd";
const manager = "0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06";
const pauser = "0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06";

async function main() {
  await deployProxyUUPS(hre, "VotingIncentive", vault, emissionVoting, adminVoter, admin, manager, pauser);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
