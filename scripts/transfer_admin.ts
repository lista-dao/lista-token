import hre from "hardhat";

const main = async () => {
  const proxyAddresses = [
    "0x564fa71EABe7683af701d32f34421Ecc118b1eBb", // ceABNBc
    "0x419352db842B7F6F33DBF541d23938cfFC181d1a", // slisBNB
    "0x88620F85Ba52a186314471D8eef7F6FCFec4A2E6", // cewBETH
    "0xc952Cc3d981Baad5d4D041721e1e179e42E6E2D5", // wBETH
    "0x73538cCe62901BD374BA314AcefC6c49EbDA0093", // wstETH
    "0xcB8f70FbC3cEcAFf9a5D53236DCb4Ef76BCcd2d6", // BTCB
    "0x7247ddB894C4dc6BE9ea7328fcfEf0a07e20F59d", // USDT
    "0x98a3fF86aF8107aBB40A706340b485e0B3E84c54", // FDUSD
    "0x7AD627aEb610d3f82466d8f9e1b9A6E1c916Da80", // STONE
    "0x5dEBc8917EF4f614B0998dDD8dE7DD421fADe245", // solvBTC
    "0xa97aed02F9Cd1D59186B3883e23eFE9f5E347900", // solvBTC.BBN
    "0x46c5721dd7275BA19010a4f0e8FEBfdf6595Be54", // sUSDX
    "0x58FE0f18507DD331ddF91Db9c111536d2a5c725A", // cePumpBTC
  ];

  for (const address of proxyAddresses) {
    const Contract = await hre.ethers.getContractFactory("BorrowLisUSDListaDistributor");
    const contract = await Contract.attach(address);
    const oldRoleAddress = "0x89e68b97466c65e215C0B13de256188867f358Ae";
    const adminRole = await contract.DEFAULT_ADMIN_ROLE();
    const adminAddress = "0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253";
    // grant admin role
    console.log(`Granting admin role to ${adminAddress} for ${address}`);
    await contract.grantRole(adminRole, adminAddress);
    console.log(`Revoking admin role from ${oldRoleAddress} for ${address}`);
    // revoke old admin role
    await contract.revokeRole(adminRole, oldRoleAddress);
    console.log(`Admin role transfer done for ${address}`);
  }
};

main()
  .then(() => {
    console.log("Success");
  })
  .catch((err) => {
    console.log(err);
  });
