import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ethers } from "hardhat";

export async function deployDirect(
  hre: HardhatRuntimeEnvironment,
  contractName: string,
  ...args: any
) {
  const Contract = await hre.ethers.getContractFactory(contractName);

  console.log(
    `Deploying ${contractName}: ${JSON.stringify(args)}, ${args.length}`
  );
  const contract = args.length
    ? await Contract.deploy(...args)
    : await Contract.deploy();

  await contract.waitForDeployment();
  const address = await contract.getAddress();

  console.log(`${contractName} deployed to:`, address);
  await hre.run("verify:verify", {
    address: address,
    constructorArguments: args,
  });
  return address;
}

export async function deployProxy(
  hre: HardhatRuntimeEnvironment,
  contractName: string,
  ...args: any
) {
  const Contract = await hre.ethers.getContractFactory(contractName);

  console.log(`Deploying proxy ${contractName}: ${args}, ${args.length}`);
  const contract = args.length
    ? await hre.upgrades.deployProxy(Contract, args)
    : await hre.upgrades.deployProxy(Contract);

  await contract.waitForDeployment();

  const proxyAddress = await contract.getAddress();

  const contractImplAddress =
    await hre.upgrades.erc1967.getImplementationAddress(proxyAddress);

  console.log(`Proxy ${contractName} deployed to:`, proxyAddress);
  console.log(`Impl ${contractName} deployed to:`, contractImplAddress);

  try {
    await hre.run("verify:verify", {
      address: contractImplAddress,
    });
    await hre.run("verify:verify", {
      address: proxyAddress,
    });
  } catch (e) {
    console.log("Error verifying contract:", e);
  }
  return proxyAddress;
}

export async function upgradeProxy(
  hre: HardhatRuntimeEnvironment,
  contractName: string,
  proxyAddress: string
) {
  const Contract = await hre.ethers.getContractFactory(contractName);

  console.log(`Upgrading ${contractName} with proxy at: ${proxyAddress}`);

  const contract = await hre.upgrades.upgradeProxy(proxyAddress, Contract);
  await contract.waitForDeployment();

  const contractImplAddress =
    await hre.upgrades.erc1967.getImplementationAddress(proxyAddress);

  console.log(`Proxy ${contractName} deployed to:`, contract.target);
  console.log(`Impl ${contractName} deployed to:`, contractImplAddress);
}

export async function validateUpgrade(
  hre: HardhatRuntimeEnvironment,
  oldContractName: string,
  newContractName: string
) {
  const OldContract = await hre.ethers.getContractFactory(oldContractName);
  const NewContract = await hre.ethers.getContractFactory(oldContractName);

  console.log(
    `Checking whether ${newContractName} is compatible with ${oldContractName}`
  );
  await hre.upgrades.validateUpgrade(OldContract, NewContract);
  console.log(
    `${newContractName} is compatible with ${oldContractName}, can be upgraded`
  );
}

export async function transferProxyAdminOwner(
  hre: HardhatRuntimeEnvironment,
  proxyAddress: string,
  newOwner: string
) {
  const PROXY_ADMIN_ABI = [
    "function transferOwnership(address newOwner) public",
    "function owner() public view returns (address)",
  ];

  const proxyAdminAddress = await getProxyAdminAddress(hre, proxyAddress);
  const proxyAdmin = await hre.ethers.getContractAt(
    PROXY_ADMIN_ABI,
    proxyAdminAddress
  );

  if (proxyAdminAddress !== hre.ethers.ZeroAddress) {
    // check if the current owner is the deployer
    const owner = await proxyAdmin.owner();
    if (owner !== newOwner) {
      console.log(
        `ProxyAdmin: ${proxyAdminAddress} Owner: ${owner} NewOwner: ${newOwner}`
      );
      await proxyAdmin.transferOwnership(newOwner);
      console.log(`ProxyAdmin Ownership Transferred Successfully...`);
    } else {
      console.log("ProxyAdmin already owned by newOwner");
    }
  } else {
    console.log("Invalid proxyAdmin address");
  }
}

export async function getProxyAdminAddress(
  hre: HardhatRuntimeEnvironment,
  proxyAddress: string
) {
  const adminSlot =
    "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";
  const proxyAdminBytes = await hre.ethers.provider.getStorage(
    proxyAddress,
    adminSlot
  );
  return parseAddress(hre, proxyAdminBytes);
}

function parseAddress(hre: HardhatRuntimeEnvironment, addressString: string) {
  const buf = Buffer.from(addressString.replace(/^0x/, ""), "hex");
  if (!buf.slice(0, 12).equals(Buffer.alloc(12, 0))) {
    return undefined;
  }
  const address = "0x" + buf.toString("hex", 12, 32); // grab the last 20 bytes

  return hre.ethers.getAddress(address);
}
