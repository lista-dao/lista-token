// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TransferLimiterV2 } from "../../../../contracts/oft/v2/TransferLimiterV2.sol";
import { ListaOFTAdapterV2 } from "../../../../contracts/oft/v2/ListaOFTAdapterV2.sol";
import { OFTConfig } from "./OFTConfig.sol";
import { OFTScriptBase } from "./OFTScriptBase.sol";

/**
 * @title DeployListaOFTAdapterV2
 * @notice Deploys the upgradeable ListaOFTAdapterV2 (UUPS proxy) on the home
 *         chain (BNB Chain mainnet / testnet), selected by `block.chainid`.
 *
 * Env:
 *   DEPLOYER_PRIVATE_KEY (required), ADMIN / MANAGER / PAUSER (optional,
 *   default = deployer).
 *
 * Usage:
 *   forge script scripts/foundry/oft/v2/DeployListaOFTAdapterV2.s.sol \
 *     --rpc-url bsc --broadcast --verify
 */
contract DeployListaOFTAdapterV2 is OFTScriptBase {
  function run() external returns (address proxy, address implementation) {
    uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer = vm.addr(pk);
    (address admin, address manager, address pauser) = _roles(deployer);

    OFTConfig.NetworkConfig memory cfg = OFTConfig.getConfig(block.chainid);
    require(cfg.isAdapter, "DeployAdapter: not an adapter chain");
    require(cfg.token != address(0), "DeployAdapter: token not set");

    console.log("Network chainId:", block.chainid);
    console.log("Deployer:", deployer);
    console.log("Admin:", admin);
    console.log("Manager:", manager);
    console.log("Pauser:", pauser);
    console.log("Locked token:", cfg.token);
    console.log("LZ endpoint:", cfg.lzEndpoint);

    TransferLimiterV2.TransferLimit[] memory limits = _limits(cfg);

    vm.startBroadcast(pk);
    ListaOFTAdapterV2 impl = new ListaOFTAdapterV2(cfg.token, cfg.lzEndpoint);
    ERC1967Proxy proxy_ = new ERC1967Proxy(
      address(impl),
      abi.encodeCall(ListaOFTAdapterV2.initialize, (admin, manager, pauser, limits))
    );
    vm.stopBroadcast();

    proxy = address(proxy_);
    implementation = address(impl);
    console.log("ListaOFTAdapterV2 proxy:", proxy);
    console.log("ListaOFTAdapterV2 implementation:", implementation);
  }
}
