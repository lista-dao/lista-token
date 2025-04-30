// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import { ListaOFT } from "../../contracts/oft/ListaOFT.sol";
import { TransferLimiter } from "../../contracts/oft/TransferLimiter.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

struct LZConfig {
  address endpoint;
  address sendLib;
  address receiveLib;
  address[] dvns;
  address executor;
  uint32 inboundConfirmations;
  uint32 outboundConfirmations;
  uint8 requiredDVNCount;
}

contract TargetChainOFTDeploymentScript is Script {

  address admin;
  address manager;
  address pauser;
  address token;
  uint256 deployerPK;
  address deployer;

  ListaOFT slisBnbOFT;
  uint32 bscChainEID;

  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {
    // get private key
    deployerPK = vm.envUint("DEPLOYER_PRIVATE_KEY");
    deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    // --- roles
    admin = vm.envOr("ADMIN", deployer);
    console.log("Admin: %s", admin);

    manager = vm.envOr("MANAGER", deployer);
    console.log("Manager: %s", manager);

    pauser = vm.envOr("PAUSER", deployer);
    console.log("Pauser: %s", pauser);

    bscChainEID = uint32(vm.envUint("SOURCE_CHAIN_EID"));
    console.log("BSC Chain EID: %s", bscChainEID);
  }

  function run() public {
    vm.startBroadcast(deployerPK);

    address oftLzEndpoint = vm.envAddress("TARGET_LZ_ENDPOINT");
    ListaOFT slisBnbOFTImpl = new ListaOFT(oftLzEndpoint);
    // Encode initialization call
    bytes memory slisBnbOFTInitData = abi.encodeWithSignature(
      "initialize(address,address,address,string,string,address)",
      admin,
      manager,
      pauser,
      "Staked Lista BNB",
      "slisBNB",
      deployer // delegate (have the right to config oApp at LZ endpoint)
    );
    // deploy proxy
    ERC1967Proxy slisBnbOFTProxy = new ERC1967Proxy(address(slisBnbOFTImpl), slisBnbOFTInitData);
    slisBnbOFT = ListaOFT(address(slisBnbOFTProxy));
    console.log("SlisBNB OFT: %s", address(slisBnbOFT));

    // configure
    wirePeer();
    setupTransferLimits();

    vm.stopBroadcast();
  }

  function wirePeer() internal {
    address OFTAdapterBscTestnet = 0xdCB059ad88644F2A9bCE8ED3dd85626e8eaE1430;
    address OFTAdapterBscMainnet = 0x837CB07f6B8a98731856092457524FF37b25E7B3;
    slisBnbOFT.setPeer(bscChainEID, bytes32(uint256(uint160(
      bscChainEID == 40102 ? OFTAdapterBscTestnet : OFTAdapterBscMainnet
    ))));
  }

  // setup transfer limits
  function setupTransferLimits() internal {
    TransferLimiter.TransferLimit[] memory limits = new TransferLimiter.TransferLimit[](1);
    limits[0] = TransferLimiter.TransferLimit(
      bscChainEID,
      100000 ether, // max Daily Transfer Amount
      10000 ether, // single Transfer Upper Limit
      0.1 ether, // single Transfer Lower Limit
      20000 ether, // daily Transfer Amount Per Address
      10 // daily Transfer Attempt Per Address
    );
    slisBnbOFT.setTransferLimitConfigs(limits);
    console.log("Transfer limits set");
  }
}
