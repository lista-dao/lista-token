import { upgradeProxy, validateUpgrade } from "../tasks";
import hre from "hardhat";

const proxyAddress = "0x4EED5fa7344d7B40c548d21f151A89bBE750F59c";

async function main() {
  await validateUpgrade(hre, "contracts/old/StakingVault.sol:StakingVault", "contracts/dao/StakingVault.sol:StakingVault");
  const OldContract = await hre.ethers.getContractFactory(
    "contracts/old/StakingVault.sol:StakingVault"
  );
  await hre.upgrades.forceImport(proxyAddress, OldContract);

  await upgradeProxy(
    hre,
    "contracts/dao/StakingVault.sol:StakingVault",
    proxyAddress
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
