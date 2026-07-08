// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TransferLimiterV2 } from "../../../../contracts/oft/v2/TransferLimiterV2.sol";
import { ListaOFTv2 } from "../../../../contracts/oft/v2/ListaOFTv2.sol";
import { OFTConfig } from "./OFTConfig.sol";
import { OFTScriptBase } from "./OFTScriptBase.sol";

/**
 * @title DeployListaOFTv2
 * @notice Deploys the upgradeable ListaOFTv2 (UUPS proxy) on a remote chain
 *         (Ethereum mainnet / Sepolia testnet), selected by `block.chainid`.
 *
 * Env:
 *   DEPLOYER_PRIVATE_KEY (required), ADMIN / MANAGER / PAUSER (optional,
 *   default = deployer).
 *
 * Usage:
 *   forge script scripts/foundry/oft/v2/DeployListaOFTv2.s.sol \
 *     --rpc-url ethereum --broadcast --verify
 */
contract DeployListaOFTv2 is OFTScriptBase {
  function run() external returns (address proxy, address implementation) {
    uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(pk);
    (address admin, address manager, address pauser) = _roles(deployer);

    OFTConfig.NetworkConfig memory cfg = OFTConfig.getConfig(block.chainid);
    require(!cfg.isAdapter, "DeployOFT: not an OFT chain");
    require(bytes(cfg.tokenName).length > 0, "DeployOFT: tokenName not set");

    console.log("Network chainId:", block.chainid);
    console.log("Deployer:", deployer);
    console.log("Admin:", admin);
    console.log("Manager:", manager);
    console.log("Pauser:", pauser);
    console.log("Token:", cfg.tokenName, cfg.symbol);
    console.log("LZ endpoint:", cfg.lzEndpoint);

    TransferLimiterV2.TransferLimit[] memory limits = _limits(cfg);

    vm.startBroadcast(pk);
    ListaOFTv2 impl = new ListaOFTv2(cfg.lzEndpoint);
    ERC1967Proxy proxy_ = new ERC1967Proxy(
      address(impl),
      abi.encodeCall(ListaOFTv2.initialize, (cfg.tokenName, cfg.symbol, admin, manager, pauser, limits))
    );
    vm.stopBroadcast();

    proxy = address(proxy_);
    implementation = address(impl);
    console.log("ListaOFTv2 proxy:", proxy);
    console.log("ListaOFTv2 implementation:", implementation);
  }
}
