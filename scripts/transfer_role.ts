import hre from "hardhat";
import Promise from "bluebird";

const ADMIN_ROLE = '0x0000000000000000000000000000000000000000000000000000000000000000';

const proxyAdminABI = [{"inputs":[{"internalType":"address","name":"initialOwner","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},{"inputs":[{"internalType":"address","name":"owner","type":"address"}],"name":"OwnableInvalidOwner","type":"error"},{"inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"OwnableUnauthorizedAccount","type":"error"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"previousOwner","type":"address"},{"indexed":true,"internalType":"address","name":"newOwner","type":"address"}],"name":"OwnershipTransferred","type":"event"},{"inputs":[],"name":"UPGRADE_INTERFACE_VERSION","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"owner","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"renounceOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"newOwner","type":"address"}],"name":"transferOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"contract ITransparentUpgradeableProxy","name":"proxy","type":"address"},{"internalType":"address","name":"implementation","type":"address"},{"internalType":"bytes","name":"data","type":"bytes"}],"name":"upgradeAndCall","outputs":[],"stateMutability":"payable","type":"function"}];

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0].address;

  const distributor = '0xf2fA32498305E6595e3D54Dc41674d0FcA207026';
  const distributorProxyAdmin = '0x658AD16C6089Fd985e2DfAaEd2EBC21A6Cfb8101';
  const admin = '0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253';

  const distributorContract = await hre.ethers.getContractAt(
    "StakeLisUSDListaDistributor",
    distributor
  );
  const proxyAdminContract = await hre.ethers.getContractAt(
    proxyAdminABI,
    distributorProxyAdmin
  );

  await Promise.delay(3000);
  await distributorContract.grantRole(ADMIN_ROLE, admin);
  await Promise.delay(3000);
  await distributorContract.revokeRole(ADMIN_ROLE, deployer);
  console.log('distributor role setup done');

  await Promise.delay(3000);
  await proxyAdminContract.transferOwnership(admin);
  console.log('proxy admin role setup done');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
