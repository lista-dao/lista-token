import { upgradeProxyUUPS } from "./tasks";
import hre from "hardhat";

async function main() {
  await upgradeProxyUUPS(hre, "VotingIncentive", "0xB43fA7d7c33c165293EA596233c1d298D3D8b973");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
