import { deployProxy } from "./tasks";
import hre from "hardhat";

const lista = "0x90b94D605E069569Adf33C0e73E26a83637c94B1";
const velista = "0x79B3286c318bdf7511A59dcf9a2E88882064eCbA";
const veListaDistributor = "0x040037d4c8cb2784d47a75Aa20e751CDB1E8971A";
const oracle = "0x79e9675cDe605Ef9965AbCE185C5FD08d0DE16B1";
const feeReceiver = "0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06";
const admin = "0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06";
const bot = "0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232";

async function main() {
  await deployProxy(
    hre,
    "VeListaAutoCompounder",
    lista,
    velista,
    veListaDistributor,
    oracle,
    feeReceiver,
    admin,
    bot
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
