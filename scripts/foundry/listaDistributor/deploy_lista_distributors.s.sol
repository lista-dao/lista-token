pragma solidity ^0.8.10;

import { Script, console } from "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BorrowListaDistributor } from "contracts/dao/BorrowListaDistributor.sol";
import { CollateralListaDistributor } from "contracts/dao/CollateralListaDistributor.sol";

contract LpProxyDeploy is Script {

  address listaVault;
  address manager;
  address admin;
  string constant name = "ListaDao";



  ////////////////////////////////////////////
  /// Make sure isMainnet is set correctly! //
  ////////////////////////////////////////////
  bool isMainnet = true;
  address lpToken = 0x12345600000000000000000000000000000000; // replace with real lpToken address
  string constant symbol = "TOKEN_SYMBOL"; // replace with real lpToken symbol
  ////////////////////////////////////////////


  function run() public {
    
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);
    console.log("Deployer: ", deployer);

    if (isMainnet) {
      listaVault = 0x307d13267f360f78005f476Fa913F8848F30292A;
      manager = 0x74E17e6996f0DDAfdA9B500ab15a3AD7c2f69307;
      admin = 0x07D274a68393E8b8a2CCf19A2ce4Ba3518735253;
    } else {
      listaVault = 0x1D70D733401169055002FB4450942F15C2F088d4;
      manager = 0x227eeaf69495E97c1E72A48785B8A041664b5a28; // router address
      admin = msg.sender;
    }


    // kickstart broadcasting transactions
    vm.startBroadcast(deployerPrivateKey);

    // Deploy CollateralListaDistributor
    CollateralListaDistributor collateralImpl = new CollateralListaDistributor(
    );
    ERC1967Proxy collateralProxy = new ERC1967Proxy(
      address(collateralImpl),
      abi.encodeWithSelector(
        CollateralListaDistributor.initialize.selector,
        name,
        string(abi.encodePacked(symbol, " CollateralListaDAODistributor")),
        admin,
        manager,
        listaVault,
        lpToken
      )
    );
    console.log("CollateralListaDistributor deployed at: ", address(collateralProxy));

    // Deploy BorrowListaDistributor
    BorrowListaDistributor borrowImpl = new BorrowListaDistributor();
    ERC1967Proxy borrowProxy = new ERC1967Proxy(
      address(borrowImpl),
      abi.encodeWithSelector(
        BorrowListaDistributor.initialize.selector,
        name,
        string(abi.encodePacked(symbol, " BorrowListaDAODistributor")),
        admin,
        manager,
        listaVault,
        lpToken
      )
    );
    console.log("BorrowListaDistributor deployed at: ", address(borrowProxy));

    vm.stopBroadcast();
  }
}
