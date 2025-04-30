// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import { ListaOFT } from "../../contracts/oft/ListaOFT.sol";
import { ListaOFTAdapter } from "../../contracts/oft/ListaOFTAdapter.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

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

interface IEndpointV2 {
  function setConfig(
    address _adapter,
    address _lib,
    SetConfigParam[] memory _configParams
  ) external;
}

contract ConfigureLzEndpointScript is Script {

  uint256 deployerPK;
  address deployer;
  ListaOFT slisBnbOFT;
  ListaOFTAdapter slisBnbOFTAdapter;
  uint32 srcChainEID;
  uint32 targetChainEID;
  mapping(uint32 eid => LZConfig) lzConfigs;

  bool fromSrcChain = true;

  // DVN addresses: https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
  // Libs: https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts

  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {
    srcChainEID = uint32(vm.envUint("SOURCE_CHAIN_EID"));
    targetChainEID = uint32(vm.envUint("TARGET_CHAIN_EID"));
    address _slisBnbOFT = vm.envAddress("OFT");
    address _slisBnbOFTAdapter = vm.envAddress("OFT_ADAPTER");
    slisBnbOFTAdapter = ListaOFTAdapter(_slisBnbOFTAdapter);
    slisBnbOFT = ListaOFT(_slisBnbOFT);

    /************************/
    //      Sonic Mainnet    //
    /************************/
    // Sonic Mainnet
    address[] memory dvns30332 = new address[](2);
    dvns30332[0] = 0x282b3386571f7f794450d5789911a9804FA346b4; // LayerZero Lab
    dvns30332[1] = 0xDd7B5E1dB4AaFd5C8EC3b764eFB8ed265Aa5445B; // Stargate
    lzConfigs[30332] = LZConfig({
      endpoint: 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B,
      sendLib: 0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7,
      receiveLib: 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043,
      dvns: dvns30332,
      executor: 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b,
      inboundConfirmations: 5,
      outboundConfirmations: 20,
      requiredDVNCount : 2
    });

    /************************/
    //     Sonic Testnet    //
    /************************/
    // @notice: for testnet we only use 1 DVN
    // BSC testnet
    address[] memory dvns40102 = new address[](1);
    dvns40102[0] = 0x0eE552262f7B562eFcED6DD4A7e2878AB897d405; // LayerZero Lab
    lzConfigs[40102] = LZConfig({
      endpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
      sendLib: 0x55f16c442907e86D764AFdc2a07C2de3BdAc8BB7,
      receiveLib: 0x188d4bbCeD671A7aA2b5055937F79510A32e9683,
      dvns: dvns40102,
      executor: 0x31894b190a8bAbd9A067Ce59fde0BfCFD2B18470,
      inboundConfirmations: 5,
      outboundConfirmations : 20,
      requiredDVNCount : 1
    });
    // Sonic Testnet (EIP ID 40349)
    address[] memory dvns40349 = new address[](1);
    dvns40349[0] = 0x88B27057A9e00c5F05DDa29241027afF63f9e6e0; // LayerZero Lab
    lzConfigs[40349] = LZConfig({
      endpoint: 0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff,
      sendLib: 0xd682ECF100f6F4284138AA925348633B0611Ae21,
      receiveLib: 0xcF1B0F4106B0324F96fEfcC31bA9498caa80701C,
      dvns: dvns40349,
      executor: 0x9dB9Ca3305B48F196D18082e91cB64663b13d014,
      inboundConfirmations: 5,
      outboundConfirmations: 20,
      requiredDVNCount : 1
    });
  }

  function run() public {
    // get private key
    deployerPK = vm.envUint("DEPLOYER_PRIVATE_KEY");
    deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    vm.startBroadcast(deployerPK);

    // CONFIG_TYPE_EXECUTOR = 1, CONFIG_TYPE_ULN = 2;
    uint32 from = srcChainEID;
    uint32 to = targetChainEID;
    if (!fromSrcChain) {
      from = targetChainEID;
      to = srcChainEID;
    }

    // get config
    LZConfig memory lzConfig = lzConfigs[from];

    // --- set Uln
    UlnConfig memory ulnConfig;
    ulnConfig.confirmations = lzConfig.outboundConfirmations;
    ulnConfig.requiredDVNCount = lzConfig.requiredDVNCount;
    ulnConfig.requiredDVNs = lzConfig.dvns;

    // DVN configs
    SetConfigParam[] memory sendConfigParams = new SetConfigParam[](1);
    sendConfigParams[0] = SetConfigParam({
      eid: to,
      configType: 2,
      config: abi.encode(ulnConfig)
    });

    // set send library config
    IEndpointV2(lzConfig.endpoint).setConfig(
      fromSrcChain ? address(slisBnbOFTAdapter) : address(slisBnbOFT),
      lzConfig.sendLib,
      sendConfigParams
    );

    // ****************************
    //  set Receive library Config
    // ****************************
    ulnConfig.confirmations = lzConfig.inboundConfirmations;

    SetConfigParam[] memory receiveConfigParams = new SetConfigParam[](1);
    receiveConfigParams[0] = SetConfigParam({
      eid: to,
      configType: 2,
      config: abi.encode(ulnConfig)
    });

    IEndpointV2(lzConfig.endpoint).setConfig(
      fromSrcChain ? address(slisBnbOFTAdapter) : address(slisBnbOFT),
      lzConfig.receiveLib,
      receiveConfigParams
    );
    vm.stopBroadcast();
  }
}
