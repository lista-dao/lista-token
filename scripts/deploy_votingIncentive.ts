import { deployProxyUUPS } from "./tasks";
import hre from "hardhat";

const admin = "0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253";
const adminVoter = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";
const vault = "0x307d13267f360f78005f476Fa913F8848F30292A";
const emissionVoting = "0xFc136f286805A7922d9Bf04317068964b231336c";
const manager = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";
const pauser = "0xEEfebb1546d88EA0909435DF6f615084DD3c5Bd8";

async function main() {
  await deployProxyUUPS(hre, "VotingIncentive", vault, emissionVoting, adminVoter, admin, manager, pauser);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
