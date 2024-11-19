import { deployDirect } from "../tasks";
import hre from "hardhat";

const stableSwap = "0xeE7c95A9e4206a1daBFb15C4F471c6D5f5e8863F";
const stableSwapInfo = "0x0A548d59D04096Bc01206D58C3D63c478e1e06dB";
const v2wrapper = "0x57117D0226AEa1490F8d9D403c56Dbca1317dF8D";

// contracts/dao/USDTLpListaDistributor.sol:USDTLpListaDistributor at 0xD720749cD757249046b9C99b781B1F9Ee4B1377E
async function main() {
  await deployDirect(hre, "USDTLpListaDistributor", stableSwap, stableSwapInfo, v2wrapper);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
