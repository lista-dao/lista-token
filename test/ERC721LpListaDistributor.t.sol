// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../contracts/VeLista.sol";
import "../contracts/ListaToken.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../contracts/dao/ERC721LpListaDistributor.sol";
import "../contracts/dao/ListaVault.sol";
import "../contracts/mock/MockERC20.sol";
import "../contracts/dao/interfaces/IDistributor.sol";

contract ERC721LpListaDistributorTest is Test {
    VeLista public veLista = VeLista(0x51075B00313292db08f3450f91fCA53Db6Bd0D11);
    ListaToken public lista = ListaToken(0x1d6d362f3b2034D9da97F0d1BE9Ff831B7CC71EB);
    ProxyAdmin public proxyAdmin = ProxyAdmin(0xc78f64Cd367bD7d2922088669463FCEE33f50b7c);
    uint256 MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    ListaVault listaVault;
    uint256 tokenId = 147928;

    IERC721 lpToken = IERC721(0x427bF5b37357632377eCbEC9de3626C71A5396c1);
    ERC721LpListaDistributor erc721Distributor;
    OracleCenter oracleCenter;
    address oracle = 0x9CCf790F691925fa61b8cB777Cb35a64F5555e53;

    address manager = 0xeA71Ec772B5dd5aF1D15E31341d6705f9CB86232;
    address user1 = 0x5a97ba0b0B18a618966303371374EBad4960B7D9;
    address user2 = 0x245b3Ee7fCC57AcAe8c208A563F54d630B5C4eD7;

    address proxyAdminOwner = 0x6616EF47F4d997137a04C2AD7FF8e5c228dA4f06;

    address token0 = 0x5b8E97Cbf8b623737bBf9F3842e3895d23a1F98E;
    address token1 = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    uint24 fee = 500;
    uint256 priceRate = 1e16;

    function setUp() public {
        vm.createSelectFork("https://bsc-testnet-dataseed.bnbchain.org");
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        vm.startPrank(manager);
        vm.stopPrank();

        vm.startPrank(proxyAdminOwner);
        ListaVault listaVaultLogic = new ListaVault();
        TransparentUpgradeableProxy listaVaultProxy = new TransparentUpgradeableProxy(
            address(listaVaultLogic),
            proxyAdminOwner,
            abi.encodeWithSignature("initialize(address,address,address,address)", manager, manager, address(lista), address(veLista))
        );
        listaVault = ListaVault(address(listaVaultProxy));

        OracleCenter oracleCenterLogic = new OracleCenter();
        TransparentUpgradeableProxy oracleCenterProxy = new TransparentUpgradeableProxy(
            address(oracleCenterLogic),
            proxyAdminOwner,
            abi.encodeWithSignature("initialize(address,address)", manager, oracle)
        );
        oracleCenter = OracleCenter(address(oracleCenterProxy));

        ERC721LpListaDistributor distributorLogic = new ERC721LpListaDistributor();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributorLogic),
            proxyAdminOwner,
            abi.encodeWithSignature("initialize(address,address,address,address,address,address,address,uint24,uint256)",
                manager, manager, address(listaVault), address(lpToken), address(oracleCenter), token0, token1, fee, priceRate)
        );

        erc721Distributor = ERC721LpListaDistributor(address(proxy));
        vm.stopPrank();

    }


    function test_deposit() public {
//        vm.startPrank(manager);
//        lpToken.approve(address(erc721Distributor), tokenId);
//        erc721Distributor.deposit(tokenId);
//        vm.stopPrank();
    }

    function tickToPrice(int24 tick) private pure returns (uint256) {
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 sqrtPrice = uint256(sqrtPriceX96)* 1e18 / (1 << 96);
        return sqrtPrice * sqrtPrice / 1e18;
    }
}
