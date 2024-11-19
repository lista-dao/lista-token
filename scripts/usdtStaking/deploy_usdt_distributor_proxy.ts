import { deployProxy } from "../tasks";
import hre from "hardhat";

const admin = "0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06";
const listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
const stakingVault = "";
const stableSwap = "0xeE7c95A9e4206a1daBFb15C4F471c6D5f5e8863F";
const stableSwapInfo = "0x0A548d59D04096Bc01206D58C3D63c478e1e06dB";
const v2wrapper = "0x57117D0226AEa1490F8d9D403c56Dbca1317dF8D";

const constructorArguments = [stableSwap, stableSwapInfo, v2wrapper];

async function main() {
  await deployProxy(hre, "USDTLpListaDistributor", admin, admin, admin, listaVault, stakingVault, {
    "constructorArgs": constructorArguments,
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
