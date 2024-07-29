import { deployProxy } from "./tasks";
import hre from "hardhat";

const admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  const listaToken = "0x1d6d362f3b2034D9da97F0d1BE9Ff831B7CC71EB";
  const veLista = "0x51075B00313292db08f3450f91fCA53Db6Bd0D11";
  await deployProxy(hre, "ListaVault", admin, admin, listaToken, veLista);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
