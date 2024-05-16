import hre, { ethers } from "hardhat";
/**
 eid = DESTINATION chain id
 source = SOURCE chain OFT contract address
 dst = DESTINATION chain OFT contract address
 */
const peers = {
  bsc: { eid: 30101, source: "", dst: "" },
  ethereum: { eid: 30102, source: "", dst: "" },
  bscTestnet: {
    eid: 40161,
    source: "0x6F8956d9b26D307f7b9742416E7a4D3AFe08DfDB",
    dst: "0x6698f6a4B537284ECAD1071C8868186f7ECC8bCb",
  },
  sepolia: {
    eid: 40102,
    source: "0x6698f6a4B537284ECAD1071C8868186f7ECC8bCb",
    dst: "0x6F8956d9b26D307f7b9742416E7a4D3AFe08DfDB",
  },
};
const sourceChain = ["bsc", "bscTestnet"];

async function main() {
  const network = hre.network.name;
  console.log("Source Network: ", network);
  const Contract = await ethers.getContractFactory(
    sourceChain.includes(network) ? "ListaOFTAdapter" : "ListaOFT"
  );
  // @ts-ignore
  const config = peers[network];
  console.log("Config: ", config);
  const contract = Contract.attach(config.source);
  // set peer
  const tx = await contract.setPeer(
    config.eid,
    ethers.utils.arrayify(ethers.utils.hexZeroPad(config.dst, 32))
  );
  console.log("tx hash: ", tx.hash);
  await tx.wait(3);
  console.log(`Chain "${network}" peer is set`);
}

main()
  .then(() => {
    console.log("Done");
  })
  .catch(console.error);
