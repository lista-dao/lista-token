import { deployDirect } from "../tasks";
import hre from "hardhat";

// PancakeStableSwapLP deployed to: 0x7B9eF7b3a0A50E83dD3065595D70f456410d3463
async function main() {
  await deployDirect(hre, "PancakeStableSwapLP");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
