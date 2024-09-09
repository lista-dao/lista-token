import hre, { ethers } from "hardhat";

const eth = '0x2170Ed0880ac9A755fd29B2688956BD959F933F8'
const lista = '0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46'
const lisusd = '0x0782b6d8c4551B9760e74c0545a9bCD90bdc41E5'
const slisbnb = '0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B'

// TODO: add contract address
const listaRevenueDistributor = "0x5525456554E7C1A7f2AB5CCd4564F45288DD8c5a"

async function main() {
  const network = hre.network.name;
  console.log("Source Network: ", network);
  const Contract = await hre.ethers.getContractFactory("ListaRevenueDistributor");
  const contract = Contract.attach(listaRevenueDistributor);
  // set token whitelist
  const tx = await contract.addTokensToWhitelist([eth, lista, lisusd, slisbnb]);
  console.log("tx hash: ", tx.hash);
  await tx.wait(3);
  console.log(
    `set token whitelist to ${JSON.stringify([eth, lista, lisusd, slisbnb])}`
  );
}

main()
  .then(() => {
    console.log("setTokens done");
  })
  .catch(console.error);

