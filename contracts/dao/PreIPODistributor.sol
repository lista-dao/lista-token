// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title PreIPODistributor
 * @author Lista
 * @dev Escrow subscription contract with two rounds per sale.
 *
 * - Whitelist round: gated by a merkle root; leaf = keccak256(abi.encode(chainid, account)).
 *   The leaf proves membership only, so one tree can be reused across sales.
 * - Public round: open to everyone, opened by the manager after the whitelist round.
 *
 * On the first deposit each address selects a delivery tranche, locked for the whole sale
 * (top-ups inherit it). The tranche does not affect accounting; it only records the choice.
 *
 * Allocation is computed off-chain; this contract only holds deposits. Deposits are locked and
 * can only be topped up, never withdrawn. Settlement and delivery are added via UUPS upgrade.
 */
contract PreIPODistributor is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER = keccak256("MANAGER");

    // Delivery tranche selected at first deposit; 0 = not selected.
    uint8 public constant TRANCHE_UNLOCKED = 1;
    uint8 public constant TRANCHE_LOCKED = 2;

    struct Sale {
        address depositToken;
        bytes32 whitelistRoot;
        // whitelist round window
        uint256 startTime;
        uint256 endTime;
        // minimum amount per single deposit, shared by both rounds
        uint256 minDeposit;
        uint256 totalDeposits;
        bool paused;
        // public round (0 = not configured)
        uint256 pubStartTime;
        uint256 pubEndTime;
        uint256 pubTotalDeposits;
    }

    // saleId => Sale
    mapping(uint64 => Sale) public sales;
    // saleId => user => cumulative whitelist-round deposit
    mapping(uint64 => mapping(address => uint256)) public deposits;
    // saleId => user => cumulative public-round deposit
    mapping(uint64 => mapping(address => uint256)) public pubDeposits;
    // saleId => user => selected tranche (locked at first deposit; 0 = unset)
    mapping(uint64 => mapping(address => uint8)) public userTranche;

    uint64 public nextSaleId;

    event CreateSale(
        uint64 indexed saleId,
        address depositToken,
        bytes32 whitelistRoot,
        uint256 startTime,
        uint256 endTime,
        uint256 minDeposit
    );

    event UpdateSale(
        uint64 indexed saleId,
        address depositToken,
        bytes32 whitelistRoot,
        uint256 startTime,
        uint256 endTime,
        uint256 minDeposit
    );

    event SetPublicRound(uint64 indexed saleId, uint256 pubStartTime, uint256 pubEndTime);

    event SetPaused(uint64 indexed saleId, bool paused);

    event DepositWhitelist(
        uint64 indexed saleId,
        address indexed account,
        uint8 tranche,
        uint256 amount,
        uint256 userTotal,
        uint256 totalDeposits
    );

    event DepositPublic(
        uint64 indexed saleId,
        address indexed account,
        uint8 tranche,
        uint256 amount,
        uint256 userTotal,
        uint256 pubTotalDeposits
    );

    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _manager) external initializer {
        require(_admin != address(0), "Invalid admin address");
        require(_manager != address(0), "Invalid manager address");

        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
    }

    /// @dev Create a sale (whitelist round). The public round is opened later via setPublicRound.
    function createSale(
        address _depositToken,
        bytes32 _whitelistRoot,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _minDeposit
    ) external onlyRole(MANAGER) returns (uint64 saleId) {
        require(_depositToken != address(0), "Invalid deposit token");
        require(_whitelistRoot != bytes32(0), "Invalid merkle root");
        require(_startTime > block.timestamp, "Invalid start time");
        require(_endTime > _startTime, "Invalid end time");
        require(_minDeposit > 0, "Invalid min deposit");

        saleId = nextSaleId++;
        Sale storage sale = sales[saleId];
        sale.depositToken = _depositToken;
        sale.whitelistRoot = _whitelistRoot;
        sale.startTime = _startTime;
        sale.endTime = _endTime;
        sale.minDeposit = _minDeposit;

        emit CreateSale(saleId, _depositToken, _whitelistRoot, _startTime, _endTime, _minDeposit);
    }

    /// @dev Update a sale's whitelist-round config. Only allowed before the sale starts.
    function updateSale(
        uint64 _saleId,
        address _depositToken,
        bytes32 _whitelistRoot,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _minDeposit
    ) external onlyRole(MANAGER) {
        Sale storage sale = sales[_saleId];
        require(sale.whitelistRoot != bytes32(0), "Invalid saleId");
        require(sale.startTime > block.timestamp, "Sale already started");
        require(_depositToken != address(0), "Invalid deposit token");
        require(_whitelistRoot != bytes32(0), "Invalid merkle root");
        require(_startTime > block.timestamp, "Invalid start time");
        require(_endTime > _startTime, "Invalid end time");
        require(_minDeposit > 0, "Invalid min deposit");

        sale.depositToken = _depositToken;
        sale.whitelistRoot = _whitelistRoot;
        sale.startTime = _startTime;
        sale.endTime = _endTime;
        sale.minDeposit = _minDeposit;

        emit UpdateSale(_saleId, _depositToken, _whitelistRoot, _startTime, _endTime, _minDeposit);
    }

    /// @dev Open / reschedule the public round; only before it starts, and strictly after the WL round.
    function setPublicRound(uint64 _saleId, uint256 _pubStartTime, uint256 _pubEndTime)
        external
        onlyRole(MANAGER)
    {
        Sale storage sale = sales[_saleId];
        require(sale.whitelistRoot != bytes32(0), "Invalid saleId");
        require(sale.pubStartTime == 0 || sale.pubStartTime > block.timestamp, "Public round started");
        require(_pubStartTime > sale.endTime, "Public must follow WL");
        require(_pubStartTime > block.timestamp, "Invalid pub start");
        require(_pubEndTime > _pubStartTime, "Invalid pub end");

        sale.pubStartTime = _pubStartTime;
        sale.pubEndTime = _pubEndTime;

        emit SetPublicRound(_saleId, _pubStartTime, _pubEndTime);
    }

    /// @dev Pause or unpause a sale (affects both rounds).
    function setPaused(uint64 _saleId, bool _paused) external onlyRole(MANAGER) {
        Sale storage sale = sales[_saleId];
        require(sale.whitelistRoot != bytes32(0), "Invalid saleId");
        sale.paused = _paused;
        emit SetPaused(_saleId, _paused);
    }

    /// @dev Whitelist-round deposit. First deposit needs a valid proof; top-ups skip it.
    ///      The tranche is locked at the first deposit in this sale.
    function depositWhitelist(uint64 _saleId, uint8 _tranche, bytes32[] calldata _proof, uint256 _amount)
        external
        nonReentrant
    {
        Sale storage sale = sales[_saleId];
        require(sale.whitelistRoot != bytes32(0), "Invalid saleId");
        require(!sale.paused, "Sale paused");
        require(block.timestamp >= sale.startTime && block.timestamp <= sale.endTime, "WL round not active");
        require(_amount >= sale.minDeposit, "Below min deposit");

        // A non-zero existing WL deposit implies the caller already passed the proof check.
        if (deposits[_saleId][msg.sender] == 0) {
            bytes32 leaf = keccak256(abi.encode(block.chainid, msg.sender));
            require(MerkleProof.verifyCalldata(_proof, sale.whitelistRoot, leaf), "Invalid proof");
        }

        uint8 tranche = _applyTranche(_saleId, _tranche);

        uint256 userTotal = deposits[_saleId][msg.sender] + _amount;
        deposits[_saleId][msg.sender] = userTotal;
        sale.totalDeposits += _amount;

        IERC20(sale.depositToken).safeTransferFrom(msg.sender, address(this), _amount);

        emit DepositWhitelist(_saleId, msg.sender, tranche, _amount, userTotal, sale.totalDeposits);
    }

    /// @dev Public-round deposit. Open to everyone; whitelist users inherit their locked tranche.
    function depositPublic(uint64 _saleId, uint8 _tranche, uint256 _amount) external nonReentrant {
        Sale storage sale = sales[_saleId];
        require(sale.whitelistRoot != bytes32(0), "Invalid saleId");
        require(sale.pubStartTime != 0, "Public round not set");
        require(!sale.paused, "Sale paused");
        require(
            block.timestamp >= sale.pubStartTime && block.timestamp <= sale.pubEndTime,
            "Public round not active"
        );
        require(_amount >= sale.minDeposit, "Below min deposit");

        uint8 tranche = _applyTranche(_saleId, _tranche);

        uint256 userTotal = pubDeposits[_saleId][msg.sender] + _amount;
        pubDeposits[_saleId][msg.sender] = userTotal;
        sale.pubTotalDeposits += _amount;

        IERC20(sale.depositToken).safeTransferFrom(msg.sender, address(this), _amount);

        emit DepositPublic(_saleId, msg.sender, tranche, _amount, userTotal, sale.pubTotalDeposits);
    }

    /// @dev Set the tranche on first deposit, or enforce it matches on subsequent deposits.
    function _applyTranche(uint64 _saleId, uint8 _tranche) private returns (uint8 tranche) {
        tranche = userTranche[_saleId][msg.sender];
        if (tranche == 0) {
            require(_tranche == TRANCHE_UNLOCKED || _tranche == TRANCHE_LOCKED, "Invalid tranche");
            userTranche[_saleId][msg.sender] = _tranche;
            tranche = _tranche;
        } else {
            require(_tranche == tranche, "Tranche locked");
        }
    }

    /// @dev Manager (multisig) safety valve; there is no normal withdrawal path.
    function emergencyWithdraw(address _token, address _to, uint256 _amount)
        external
        onlyRole(MANAGER)
    {
        require(_to != address(0), "Invalid recipient");
        require(_amount > 0, "Invalid amount");

        if (_token == address(0)) {
            (bool success,) = payable(_to).call{value: _amount}("");
            require(success, "Transfer native failed");
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }

        emit EmergencyWithdraw(_token, _to, _amount);
    }

    function getSale(uint64 _saleId) external view returns (Sale memory) {
        return sales[_saleId];
    }

    function getSales(uint64[] calldata _saleIds) external view returns (Sale[] memory) {
        Sale[] memory _sales = new Sale[](_saleIds.length);
        for (uint256 i = 0; i < _saleIds.length; i++) {
            _sales[i] = sales[_saleIds[i]];
        }
        return _sales;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
