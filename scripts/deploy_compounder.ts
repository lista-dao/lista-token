import { deployProxy } from "./tasks";
import hre from "hardhat";

const lista = "0xFceB31A79F71AC9CBDCF853519c1b12D379EdC46";
const velista = "0xd0C380D31DB43CD291E2bbE2Da2fD6dc877b87b3";
const veListaDistributor = "0x45aAc046Bc656991c52cf25E783c6942425ce40C";
const oracle = "0xf3afD82A4071f272F403dC176916141f44E6c750";
const feeReceiver = "0x34B504A5CF0fF41F8A480580533b6Dda687fa3Da";
const admin = "0x8d388136d578dCD791D081c6042284CED6d9B0c6";
const bot = "0x6dD696c8DBa8764D0e5fD914A470FD5e780D0D12";

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
