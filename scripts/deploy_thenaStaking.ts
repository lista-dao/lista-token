import { deployDirect, deployProxy } from "./tasks";
import hre from "hardhat";
import Promise from "bluebird";

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  // todo
  const thenaVault = "";

  const address = await deployProxy(hre, "ThenaStaking", deployer, thenaVault);

  const thenaStakingContract = await hre.ethers.getContractAt(
    "ThenaStaking",
    address
  );
  const thenaVaultContract = await hre.ethers.getContractAt(
    "StakingVault",
    thenaVault
  );

  await thenaVaultContract.setStaking(address);

  await Promise.delay(3000);

  const pools = [
    // Thena slisBNB/BNB correlated
    {
      lpToken: "0x3685502Ea3EA4175FB5cBB5344F74D2138A96708",
      pool: "0x7Db93DC92ecA0c59c530A0c4bCD26a7bf363d5D1",
      distributor: "0xFf5ed1E64aCA62c822B178FFa5C36B40c112Eb00",
    },
    // Thena lisUSD/FRAX stable
    {
      lpToken: "0x04d6115703b0127888323F142B8046C7c13f857d",
      pool: "0xe5F912110Bb8A7F44634D82775d6106c11043a89",
      distributor: "0x1Cf9c6D475CdcA67942d41B0a34BD9cB9D336C4d",
    },
    // Thena lisUSD/USDT cl stable
    {
      lpToken: "0xDf0B9b59E92A2554dEdB6F6F4AF6918d79DD54c4",
      pool: "0x2Da06b6338f3d503cb2F0ee0e66C8e98A6d8001C",
      distributor: "0xC23d348f9cC86dDB059ec798e87E7F76FBC077C1",
    },
    // Thena lisUSD/frxETH norrow
    {
      lpToken: "0x69E8c26050dAECF8e3b3334e3F612B70f8D40A4F",
      pool: "0x3C2bff1BcDD838646182cFcC081e05E85A713FdB",
      distributor: "0x9B4FcbC3a01378B85d81DEFbaf9359155718be4a",
    },
    // Thena lisUSD/frxETH wide
    {
      lpToken: "0xa4d37759a64dF0e2b246945e81B50aF7628a275E",
      pool: "0xfcE6eFCdf42F6b4e5B48884889934c006B3D8bAe",
      distributor: "0x11bf1122871e13c13466681022C74B496B59147a",
    },
    // Thena lisUSD/BNB norrow
    {
      lpToken: "0x91fa468D7703C773D4528bD0C50156403bAD0252",
      pool: "0x5aCebBE0d2a2486FD10765396c6dFb95C8521d08",
      distributor: "0x39D099F6A78c7Cef7a527f55c921E7e1EE39716a",
    },
    // Thena lisUSD/BNB wide
    {
      lpToken: "0x9E1101C2FA1e5aFC8a06364F4E6bf5f672C30F68",
      pool: "0x6585Fb1E525d8590788b0E54eea10C4B8E7E53d1",
      distributor: "0x9f6C251C3122207Adf561714C1171534B569eFf4",
    },
    // Thena lisUSD/BNB ichi
    {
      lpToken: "0x885711BeDd3D17949DFEd5E77D5aB6E89c3DFc8C",
      pool: "0x6090B7C4Ea9C1c0d6b3E9e9277b2aaCbd8160981",
      distributor: "0xF6aB5cfdB46357f37b0190b793fB199D62Dcf504",
    },
  ];

  for (const pool of pools) {
    await thenaStakingContract.registerPool(
      pool.lpToken,
      pool.pool,
      pool.distributor
    );
  }

  console.log("deploy and setup contract done");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
