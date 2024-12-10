import { transferProxyAdminOwner } from "./tasks";
import hre from "hardhat";

const main = async () => {
  const proxyAddresses = [
    "0x307d13267f360f78005f476Fa913F8848F30292A", // ListaVault
    "0x0AED860cA496600F6976219Cb1acEc435d7F4f3B", // BorrowLisUSDListaDistributor
    "0xFeB28443692216f66D14C7be4a449a765E2BDbAc", // StakeLisUSDListaDistributor
    "0x946a68b29149f819FBcE866cED3632e0C9F7C53b", // OracleCenter
    "0xaDe6D976c0d8CE99ee4D15311960eD36b18bEA2f", // SlisBnbDistributor
    "0x3665d70c050ab2d46A3F5510Db0C98658094D9c9", // erc721 slisBNB/BNB v3 LP
    "0x398df8DDefB25a4e0FB740b5ae7c716Cd9eC2596", // erc721 lisUSD/WBNB v3 LP
    "0x16C39b6EE97d3d92f570ad9403418E43eA0622a5", // erc721 lisUSD/BTCB v3 LP
    "0xE43fE85d8d1d4623B9E91C094BedA7aDbB14f520", // erc721 lisUSD/ETH v3 LP
    "0xE5c03cCeb62262c7Af8C85e8474c06fa3F43DE08", // erc721 lisUSD/USDT v3 LP
    "0xe8f4644637f127aFf11F9492F41269eB5e8b8dD2", // erc20 lisUSD/USDT pancake stable pool
    "0xFf5ed1E64aCA62c822B178FFa5C36B40c112Eb00", // erc20 slisBNB/BNB thena correlated LP
    "0x1Cf9c6D475CdcA67942d41B0a34BD9cB9D336C4d", // erc20 lisUSD/FRAX(stable) thena LP
    "0x9B4FcbC3a01378B85d81DEFbaf9359155718be4a", // erc20 lisUSD/frxETH thena narrow LP
    "0x11bf1122871e13c13466681022C74B496B59147a", // erc20 lisUSD/frxETH thena wide LP
    "0x39D099F6A78c7Cef7a527f55c921E7e1EE39716a", // erc20 lisUSD/BNB thena narrow LP
    "0x9f6C251C3122207Adf561714C1171534B569eFf4", // erc20 lisUSD/BNB thena wide LP
    "0xF6aB5cfdB46357f37b0190b793fB199D62Dcf504", // erc20 lisUSD/BNB thena ICHI LP
    "0x3b239391C48f0B46d31D39F79Dcf64D3575e6086", // erc20 lisUSD venus isolated lending pool
    "0x05570C903A99f59E8F9913D4d628796BAD7115C3", // erc20 slisBNB venus isolated lending pool
    "0x4b2D67Bf25245783Fc4C33a48962775437F9159c", // erc20 LISTA/USDT(norraw) thena LP
    "0xb691624b69BbB23b8Cc9847B5E8c151d75110eD4", // erc721 LISTA/BNB v3 LP
    "0x8453CD3d1588E62D5e72A8bC16A8a0300A16005f", // erc721 LISTA/USDT v3 LP
  ];
  const newOwner = "0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253";
  // transfer proxy admin ownership
  for (let i = 0; i < proxyAddresses.length; i++) {
    await transferProxyAdminOwner(hre, proxyAddresses[i], newOwner);
  }
};

main()
  .then(() => {
    console.log("Success");
  })
  .catch((err) => {
    console.log(err);
  });
