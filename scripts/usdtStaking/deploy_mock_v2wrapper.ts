import { deployProxy } from "../tasks";
import hre from "hardhat";

const cake = "0x63708EeD5Ee45D9F3f6fEb5D0F4a26F63FCC3AE0";
const lpToken = "0x5eBFbF56048575d37C033843F2AC038885EBB636";

// Proxy MockPancakeV2Wrapper deployed to: 0x57117D0226AEa1490F8d9D403c56Dbca1317dF8D
async function main() {
  await deployProxy(hre, "MockPancakeV2Wrapper", cake, lpToken);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
