import { deployProxy } from "./tasks";
import hre from "hardhat";

const admin = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  // pancake
  // lisUSD/USDT pancake stable pool
  await deployERC20Distributor(
    "lisUSD/USDT pancake stable pool",
    "0xB2Aa63f363196caba3154D4187949283F085a488"
  );

  // thena
  // slisBNB/BNB thena correlated LP
  await deployERC20Distributor(
    "slisBNB/BNB thena correlated LP",
    "0x3685502Ea3EA4175FB5cBB5344F74D2138A96708"
  );
  // lisUSD/FRAX(stable) thena LP
  await deployERC20Distributor(
    "lisUSD/FRAX(stable) thena LP",
    "0x04d6115703b0127888323f142b8046c7c13f857d"
  );
  // lisUSD/USDT(cl stable) thena LP
  await deployERC20Distributor(
    "lisUSD/USDT(cl stable) thena LP",
    "0xdf0b9b59e92a2554dedb6f6f4af6918d79dd54c4"
  );
  // lisUSD/frxETH thena narrow LP
  await deployERC20Distributor(
    "lisUSD/frxETH thena narrow LP",
    "0x69e8c26050daecf8e3b3334e3f612b70f8d40a4f"
  );
  // lisUSD/frxETH thena wide LP
  await deployERC20Distributor(
    "lisUSD/frxETH thena wide LP",
    "0xa4d37759a64df0e2b246945e81b50af7628a275e"
  );
  // lisUSD/BNB thena narrow LP
  await deployERC20Distributor(
    "lisUSD/BNB thena narrow LP",
    "0x91fa468d7703c773d4528bd0c50156403bad0252"
  );
  // lisUSD/BNB thena wide LP
  await deployERC20Distributor(
    "lisUSD/BNB thena wide LP",
    "0x9e1101c2fa1e5afc8a06364f4e6bf5f672c30f68"
  );
  // lisUSD/BNB thena ICHI LP
  await deployERC20Distributor(
    "lisUSD/BNB thena ICHI LP",
    "0x885711bedd3d17949dfed5e77d5ab6e89c3dfc8c"
  );

  // venus
  // lisUSD venus isolated lending pool
  await deployERC20Distributor(
    "lisUSD venus isolated lending pool",
    "0xCa2D81AA7C09A1a025De797600A7081146dceEd9"
  );
  // slisBNB venus isolated lending pool
  await deployERC20Distributor(
    "slisBNB venus isolated lending pool",
    "0xd3CC9d8f3689B83c91b7B59cAB4946B063EB894A"
  );
}

async function deployERC20Distributor(name: string, lpToken: any) {
  let listaVault;
  if (hre.network.name === "bsc") {
    // todo
    listaVault = "";
  } else if (hre.network.name === "bscTestnet") {
    listaVault = "0x1D70D733401169055002FB4450942F15C2F088d4";
  }
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  const address = await deployProxy(
    hre,
    "ERC20LpListaDistributor",
    deployer,
    deployer,
    listaVault,
    lpToken
  );
  const contract = await hre.ethers.getContractAt("ListaVault", listaVault);

  await contract.registerDistributor(address);

  console.log(`${name} deployed to: ${address}`);
  await contract.waitForDeployment();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
