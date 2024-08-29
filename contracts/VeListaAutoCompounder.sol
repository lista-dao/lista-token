// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IVeLista.sol";
import "./interfaces/IVeListaDistributor.sol";
import "./dao/interfaces/OracleInterface.sol";

/**
 * @title VeListaAutoCompounder
 * @dev According to [LIP-001](https://snapshot.org/#/listavote.eth/proposal/0x415d54c2b9c85d9b4b631ab2f2b9a9aebfeaddb5cd116e0d0d742db0e51f7236), the veLista rewards will be converted into single token(LISTA) for distribution.
 *      This contract implements the auto-compounding feature for the veLista rewards.
 */
contract VeListaAutoCompounder is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public lista;

    // The address of the oracle; used to get the price of LISTA
    OracleInterface public oracle;

    IVeLista public veLista;
    IVeListaDistributor public veListaDistributor;

    // The address to receive the accrued auto-compounding fee
    address public feeReceiver;

    // The fee rate (bps) for auto-compounding
    // 300 by default (3%)
    uint256 public feeRate;

    // The maximum fee rate (bps) for auto-compounding
    // 10% by default
    uint256 public maxFeeRate;

    // The maximum fee for auto-compounding
    // $10 by default
    uint256 public maxFee;

    // The minimum USD value required to lock for auto compounding
    // $5 by default
    uint256 public autoCompoundThreshold;

    // user => auto compound enabled or not
    mapping(address => bool) public autoCompoundEnabled;

    // The total auto-compounding fee collected (in LISTA)
    uint256 public totalFee;

    bytes32 public constant BOT = keccak256("BOT");

    /********************** Events ***********************/
    event VeListaDistributorUpdated(address indexed _veListaDistributor);
    event OracleUpdated(address indexed _oracle);
    event AutoCompoundStatus(address indexed _account, bool _enabled);
    event AutoCompounded(
        address indexed _account,
        address _lista,
        uint256 _claimedAmount,
        uint256 _amtToCompound
    );
    event FeeWithdrawn(address indexed _receiver, uint256 _fee);
    event FeeReceiverUpdated(address indexed _newReceiver);

    function initialize(
        address _lista,
        address _velista,
        address _veListaDistributor,
        address _oracle,
        address _feeReceiver,
        address _admin,
        address _bot
    ) public initializer {
        require(
            _lista != address(0) &&
                _velista != address(0) &&
                _veListaDistributor != address(0) &&
                _feeReceiver != address(0) &&
                _admin != address(0) &&
                _bot != address(0) &&
                _oracle != address(0),
            "Zero address provided"
        );
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(BOT, _bot);

        lista = IERC20(_lista);
        veLista = IVeLista(_velista);
        require(lista == veLista.token(), "Invalid Lista token");

        veListaDistributor = IVeListaDistributor(_veListaDistributor);
        require(veLista == veListaDistributor.veLista(), "Invalid veLista");

        oracle = OracleInterface(_oracle);
        feeReceiver = _feeReceiver;

        feeRate = 300; // 3%
        maxFeeRate = 1000; // 10%
        require(
            feeRate <= maxFeeRate && maxFeeRate <= 10000,
            "Invalid fee rate"
        );

        autoCompoundThreshold = 5 * 1e18; // $5
        maxFee = 10 * 1e18; // $10
        require(
            (feeRate * autoCompoundThreshold) / 10000 <= maxFee,
            "Invalid fee"
        );

        emit VeListaDistributorUpdated(_veListaDistributor);
        emit OracleUpdated(_oracle);
        emit FeeReceiverUpdated(_feeReceiver);
    }

    /**
     * @dev Auto-compound the veLista rewards for an account; only callable by Bot
     *      Claim LISTA from veListaDistributor and then compound LISTA by doing `increaseAmountFor`.
     *
     */
    function claimAndIncreaseAmount(address account, uint16 toWeek) public onlyRole(BOT) {
        require(autoCompoundEnabled[account], "Auto compound not enabled");

        IVeLista.AccountData memory data = veLista.getLockedData(account);
        require(data.locked > 0, "No locked amount");

        (uint256 claimableAmt, ) = veListaDistributor.getTokenClaimable(
            account,
            address(lista),
            toWeek
        );
        require(
            claimableAmt > 0 && isEligibleForAutoCompound(claimableAmt),
            "Not eligible for auto compound"
        );

        uint256 claimedAmount = veListaDistributor.claimForCompound(
            account,
            address(lista),
            toWeek
        );
        uint256 amtToCompound = getAmountToCompound(claimedAmount);

        IVeLista(veLista).increaseAmountFor(account, amtToCompound);

        totalFee += claimedAmount - amtToCompound;

        emit AutoCompounded(account, address(lista), claimedAmount, amtToCompound);
    }

    function withdrawFee() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(totalFee > 0, "No fee to withdraw");

        uint256 fee = totalFee;
        totalFee = 0;

        lista.safeTransfer(feeReceiver, fee);
        emit FeeWithdrawn(feeReceiver, fee);
    }

    /**
     * @notice Enable auto-compound for the caller
     */
    function enableAutoCompound() external {
        require(!autoCompoundEnabled[msg.sender], "Auto compound already enabled");
        autoCompoundEnabled[msg.sender] = true;
        emit AutoCompoundStatus(msg.sender, true);
    }

    /**
     * @notice Disable auto-compound for the caller
     */
    function disableAutoCompound() external {
        require(autoCompoundEnabled[msg.sender], "Auto compound already disabled");
        autoCompoundEnabled[msg.sender] = false;
        emit AutoCompoundStatus(msg.sender, false);
    }

    /**
     * @dev Check if the amount is eligible for auto-compounding
     * @param _amount The amount of Lista
     */
    function isEligibleForAutoCompound(
        uint256 _amount
    ) public view returns (bool) {
        uint256 price = oracle.peek(address(lista));
        uint256 value = (_amount * price) / 1e8;

        return value >= autoCompoundThreshold;
    }

    /**
     * @notice Calculate the amount of Lista to be compounded. Reward amount * (10000 - feeRate) / 10000,
     *         if the amount is greater than maxFee, return maxFee.
     * @param _rewardAmount The amount of Lista
     */
    function getAmountToCompound(
        uint256 _rewardAmount
    ) public view returns (uint256 _amtToCompound) {
        uint256 feeAmount = (_rewardAmount * feeRate) / 10000;
        uint256 price = oracle.peek(address(lista));
        uint256 feeValue = (feeAmount * price) / 1e8;

        if (feeValue >= maxFee) {
            _amtToCompound = _rewardAmount - (maxFee * 1e8) / price;
        } else {
            _amtToCompound = _rewardAmount - feeAmount;
        }
    }

    /**
     * @dev Update the contract variables
     * @param what The variable to update; bytes32 encoded of the state variable name
     * @param data The new value
     */
    function file(
        bytes32 what,
        uint256 data
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (what == "feeRate") {
            require(data <= maxFeeRate, "Invalid feeRate");
            feeRate = data;
        } else if (what == "maxFeeRate") {
            require(feeRate <= data && data <= 10000, "Invalid maxFeeRate");
            maxFeeRate = data;
        } else if (what == "maxFee") {
            require(
                (feeRate * autoCompoundThreshold) / 10000 <= data,
                "Invalid maxFee"
            );
            maxFee = data;
        } else if (what == "autoCompoundThreshold") {
            require(
                (feeRate * data) / 10000 <= maxFee,
                "Invalid autoCompoundThreshold"
            );
            autoCompoundThreshold = data;
        } else {
            revert("Unrecognized variable");
        }
    }

    /**
     * @dev Update the stored addresses
     * @param what The contract address to update; bytes32 encoded of the contract(state variable) name
     * @param data The new value
     */
    function file(
        bytes32 what,
        address data
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(data != address(0), "Zero address provided");
        if (what == "lista") {
            require(data != address(lista), "lista already set");
            require(data == address(veLista.token()), "Invalid Lista token");
            lista = IERC20(data);
        } else if (what == "veLista") {
            require(data != address(veLista), "veLista already set");
            require(
                data == address(veListaDistributor.veLista()),
                "Invalid veLista"
            );
            veLista = IVeLista(data);
        } else if (what == "veListaDistributor") {
            require(
                data != address(veListaDistributor),
                "veListaDistributor already set"
            );
            veListaDistributor = IVeListaDistributor(data);
            emit VeListaDistributorUpdated(data);
        } else if (what == "oracle") {
            require(data != address(oracle), "oracle already set");
            oracle = OracleInterface(data);
            emit OracleUpdated(data);
        } else if (what == "feeReceiver") {
            require(data != feeReceiver, "feeReceiver already set");
            feeReceiver = data;
            emit FeeReceiverUpdated(data);
        } else {
            revert("Unrecognized variable");
        }
    }
}
