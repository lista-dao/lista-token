pragma solidity ^0.8.10;

import "./interfaces/IStaking.sol";
import "./interfaces/IStakingVault.sol";
import "./interfaces/IStakingVault.sol";
import "./interfaces/IPancakeSwapV3LpStakingVault.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract LpProxy is OwnableUpgradeable {
    // lista vault address
    address listaVault;
    // cake vault address
    address cakeVault;
    // thena vault address
    address thenaVault;
    // PancakeSwap V3 staking vault
    address pcsV3LpVault;

    // distributor address -> vault address
    mapping(address => address) public distributorToVault;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
      * @dev initialize contract
      * @param _owner owner address
      */
    function initialize(address _owner) public initializer {
        require(_owner != address(0), "owner cannot be zero address");
        __Ownable_init();
        transferOwnership(_owner);
    }

    /**
      * @dev set lista vault address
      * @param _listaVault lista vault address
     */
    function setListaVault(address _listaVault) external onlyOwner {
        require(_listaVault != address(0), "listaVault cannot be zero address");
        listaVault = _listaVault;
    }

    /**
      * @dev set cake vault address
      * @param _cakeVault cake vault address
     */
    function setCakeVault(address _cakeVault) external onlyOwner {
        require(_cakeVault != address(0), "cakeVault cannot be zero address");
        cakeVault = _cakeVault;
    }

    /**
      * @dev set thena vault address
      * @param _thenaVault thena vault address
     */
    function setThenaVault(address _thenaVault) external onlyOwner {
        require(_thenaVault != address(0), "thenaVault cannot be zero address");
        thenaVault = _thenaVault;
    }

    /**
      * @dev set pcsV3Lp vault address
      * @param _pcsV3LpVault pcsV3Lp vault address
     */
    function setPcsV3LpVault(address _pcsV3LpVault) external onlyOwner {
        require(_pcsV3LpVault != address(0), "pcsV3LpVault cannot be zero address");
        pcsV3LpVault = _pcsV3LpVault;
    }

    /**
      * @dev claim all rewards
      * @param distributors distributor addresses
     */
    function claimAll(address[] memory distributors) public {
        address account = msg.sender;
        // claim lista rewards
        IStakingVault(listaVault).batchClaimRewardsWithProxy(account, distributors);

        // distinguish between thena and cake distributors
        uint256 cakeLength;
        uint256 thenaLength;
        for (uint256 i = 0; i < distributors.length; i++) {
            if (distributorToVault[distributors[i]] == cakeVault) {
                cakeLength++;
            } else if (distributorToVault[distributors[i]] == thenaVault) {
                thenaLength++;
            }
        }

        address[] memory cakeDistributors = new address[](cakeLength);
        address[] memory thenaDistributors = new address[](thenaLength);
        uint256 cakeIdx;
        uint256 thenaIdx;
        if (cakeLength > 0 || thenaLength > 0) {
            for (uint256 i = 0; i < distributors.length; i++) {
                if (distributorToVault[distributors[i]] == cakeVault) {
                    cakeDistributors[cakeIdx] = distributors[i];
                    ++cakeIdx;
                } else if (distributorToVault[distributors[i]] == thenaVault) {
                    thenaDistributors[thenaIdx] = distributors[i];
                    ++thenaIdx;
                }
            }
            // claim cake rewards
            if (cakeLength > 0) {
                IStakingVault(cakeVault).batchClaimRewardsWithProxy(account, cakeDistributors);
            }

            // claim thena rewards
            if (thenaLength > 0) {
                IStakingVault(thenaVault).batchClaimRewardsWithProxy(account, thenaDistributors);
            }
        }
    }

    /**
      * @dev claim all rewards including pcsV3Lp rewards
      * @param distributors distributor addresses
      * @param providers providers addresses
      * @param tokenIds token ids for each provider
     */
    function claimAll(
        address[] memory distributors,
        address[] memory providers,
        uint256[][] memory tokenIds) external {
        // backward compatible
        claimAll(distributors);
        // claim pcsV3Lp rewards if any
        if (providers.length > 0) {
            require(providers.length == tokenIds.length, "Invalid providers/tokenIds length");
            // claim pcsV3Lp rewards
            IPancakeSwapV3LpStakingVault(pcsV3LpVault).batchClaimRewardsWithProxy(msg.sender, providers, tokenIds);
        }
    }

    /**
      * @dev set distributor to vault mapping
      * @param distributor distributor address
      * @param vault vault address
     */
    function setDistributorToVault(address distributor, address vault) external onlyOwner {
        require(vault == cakeVault || vault == thenaVault, "Invalid vault address");
        distributorToVault[distributor] = vault;
    }
}
