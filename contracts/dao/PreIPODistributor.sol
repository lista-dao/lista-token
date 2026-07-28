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
 * Allocation is computed off-chain; the contract holds deposits and, after the review window,
 * a finalized settlement merkle root drives claims. Deposits are locked and can only be topped
 * up, never withdrawn by the user. Claiming pays the refund and, for the unlocked tranche,
 * delivers the share token; the locked tranche only records the amount for off-chain delivery.
 */
contract PreIPODistributor is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant BOT = keccak256("BOT");

    // Delivery tranche, selected at an account's first deposit and locked for the sale; 0 = not selected.
    // On claim, TRANCHE_UNLOCKED transfers the share token to the account immediately, while
    // TRANCHE_LOCKED only records the share amount (delivered off-chain at maturity).
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

    struct Settlement {
        bytes32 root;               // finalized settlement root; claims verify against this
        bytes32 pendingRoot;        // pending root awaiting finalize (0 = none pending)
        uint256 pendingTotalRefund; // total refund committed by the pending root
        uint256 totalRefund;        // total refund committed by the finalized root
        uint256 lastSetTime;        // block time the pending root was set
        uint256 refunded;           // cumulative refund already paid out via claim
    }

    // saleId => Settlement
    mapping(uint64 => Settlement) public settlements;

    // saleId => account => claimed
    mapping(uint64 => mapping(address => bool)) public claimed;

    // review window between setSettlementRoot (step 1) and finalizeSettlement (step 2); min 6h
    uint256 public waitingPeriod;

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

    event ChangeUserTranche(uint64 indexed saleId, address indexed account, uint8 oldTranche, uint8 newTranche);

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

    event SetSettlementRoot(uint64 indexed saleId, bytes32 pendingRoot, uint256 totalRefund, uint256 setTime);

    event FinalizeSettlement(uint64 indexed saleId, bytes32 root, uint256 finalizeTime);

    event RevokeSettlementRoot(uint64 indexed saleId);

    event WaitingPeriodUpdated(uint256 waitingPeriod);

    event Claimed(
        uint64 indexed saleId,
        address indexed account,
        uint256 refundAmount,
        address shareToken,
        uint256 tokenAmount,
        uint8 tranche
    );

    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _manager, address _bot) external initializer {
        require(_admin != address(0), "Invalid admin address");
        require(_manager != address(0), "Invalid manager address");
        require(_bot != address(0), "Invalid bot address");

        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(MANAGER, _manager);
        _setupRole(BOT, _bot);

        // MANAGER manages the BOT role
        _setRoleAdmin(BOT, MANAGER);
    }

    /// @dev Initializes settlement/claim state introduced by this version. Runs once, after the
    ///      upgrade — call it atomically via upgradeToAndCall(newImpl, abi.encodeCall(initializeV2, ())).
    function initializeV2() external reinitializer(2) {
        waitingPeriod = 6 hours;
        emit WaitingPeriodUpdated(waitingPeriod);
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
        // if a public round is already scheduled, the WL round must still end before it starts
        require(sale.pubStartTime == 0 || _endTime < sale.pubStartTime, "WL end must precede public");
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
        // cannot open/reschedule a public round once settlement is pending or finalized
        require(
            settlements[_saleId].pendingRoot == bytes32(0) && settlements[_saleId].root == bytes32(0),
            "Settlement started"
        );
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

    /// @dev MANAGER correction of an account's locked tranche. Allowed until the settlement root
    ///      is finalized; a pending (not-yet-finalized) root does not block it, but the pending
    ///      root must then be revoked and rebuilt off-chain to reflect the change. Deposit amounts
    ///      are untouched; the tranche never affects on-chain accounting.
    function changeUserTranche(uint64 _saleId, address _account, uint8 _tranche)
        external
        onlyRole(MANAGER)
    {
        Sale storage sale = sales[_saleId];
        require(sale.whitelistRoot != bytes32(0), "Invalid saleId");
        require(settlements[_saleId].root == bytes32(0), "Settlement finalized");
        require(_tranche == TRANCHE_UNLOCKED || _tranche == TRANCHE_LOCKED, "Invalid tranche");
        uint8 oldTranche = userTranche[_saleId][_account];
        require(oldTranche != 0, "Tranche not set");
        require(_tranche != oldTranche, "Same tranche");

        userTranche[_saleId][_account] = _tranche;
        emit ChangeUserTranche(_saleId, _account, oldTranche, _tranche);
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
        uint256 prior = deposits[_saleId][msg.sender];
        if (prior == 0) {
            bytes32 leaf = keccak256(abi.encode(block.chainid, msg.sender));
            require(MerkleProof.verifyCalldata(_proof, sale.whitelistRoot, leaf), "Invalid proof");
        }

        uint8 tranche = _applyTranche(_saleId, _tranche);

        uint256 userTotal = prior + _amount;
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

    /// @dev Set the pending settlement root (step 1 of 2); starts the review window.
    ///      A new pending root cannot be set while one is already in flight.
    function setSettlementRoot(uint64 _saleId, bytes32 _root, uint256 _totalRefund)
        external
        onlyRole(BOT)
    {
        Sale storage sale = sales[_saleId];
        require(sale.whitelistRoot != bytes32(0), "Invalid saleId");
        require(!sale.paused, "Sale paused");
        // deposit windows must be closed so no deposit can land after the off-chain snapshot
        require(block.timestamp > sale.endTime, "WL round not ended");
        require(sale.pubStartTime == 0 || block.timestamp > sale.pubEndTime, "Public round not ended");

        Settlement storage s = settlements[_saleId];
        // settlement is single-shot: once a root is finalized it cannot be replaced
        require(s.root == bytes32(0), "Already finalized");
        require(_root != bytes32(0), "Invalid root");
        require(s.pendingRoot == bytes32(0), "Pending root in flight");
        require(_totalRefund <= sale.totalDeposits + sale.pubTotalDeposits, "Refund exceeds deposits");

        s.pendingRoot = _root;
        s.pendingTotalRefund = _totalRefund;
        s.lastSetTime = block.timestamp;

        emit SetSettlementRoot(_saleId, _root, _totalRefund, block.timestamp);
    }

    /// @dev Finalize the pending settlement root (step 2 of 2); only after the review window.
    function finalizeSettlement(uint64 _saleId) external onlyRole(BOT) {
        require(!sales[_saleId].paused, "Sale paused");
        Settlement storage s = settlements[_saleId];
        require(s.pendingRoot != bytes32(0), "No pending root");
        require(block.timestamp >= s.lastSetTime + waitingPeriod, "Review window not passed");

        s.root = s.pendingRoot;
        s.totalRefund = s.pendingTotalRefund;
        s.pendingRoot = bytes32(0);
        s.pendingTotalRefund = 0;

        emit FinalizeSettlement(_saleId, s.root, block.timestamp);
    }

    /// @dev Revoke the pending settlement root before it is finalized.
    function revokeSettlementRoot(uint64 _saleId) external onlyRole(MANAGER) {
        Settlement storage s = settlements[_saleId];
        require(s.pendingRoot != bytes32(0), "No pending root");
        s.pendingRoot = bytes32(0);
        s.pendingTotalRefund = 0;
        emit RevokeSettlementRoot(_saleId);
    }

    /// @dev Claim a finalized allocation (whitelist + public rounds combined), once per account.
    ///      Pays the refund; for the unlocked tranche also transfers the share token, while the
    ///      locked tranche only records the amount (delivered off-chain at maturity). Permanent.
    ///      Permissionless: anyone may call it on behalf of any account; the refund and any share
    ///      delivery always go to `_account` (the address bound in the leaf), never to msg.sender.
    /// @param _saleId Sale id
    /// @param _account Account the allocation belongs to and that receives refund/shares
    /// @param _refundAmount Refund amount in the deposit token (part of the leaf)
    /// @param _shareToken Share token to deliver for the unlocked tranche (part of the leaf)
    /// @param _tokenAmount Share amount (delivered for unlocked, recorded for locked; part of the leaf)
    /// @param _proof Merkle proof of the leaf against the finalized settlement root
    function claim(
        uint64 _saleId,
        address _account,
        uint256 _refundAmount,
        address _shareToken,
        uint256 _tokenAmount,
        bytes32[] calldata _proof
    ) external nonReentrant {
        require(!sales[_saleId].paused, "Sale paused");
        Settlement storage s = settlements[_saleId];
        require(s.root != bytes32(0), "Not finalized");
        require(!claimed[_saleId][_account], "Already claimed");

        bytes32 leaf =
            keccak256(abi.encode(block.chainid, _saleId, _account, _refundAmount, _shareToken, _tokenAmount));
        require(MerkleProof.verifyCalldata(_proof, s.root, leaf), "Invalid proof");

        claimed[_saleId][_account] = true;

        uint8 tranche = userTranche[_saleId][_account];

        if (_refundAmount > 0) {
            // aggregate refunds can never exceed the committed total
            require(s.refunded + _refundAmount <= s.totalRefund, "Refund over total");
            s.refunded += _refundAmount;
            IERC20(sales[_saleId].depositToken).safeTransfer(_account, _refundAmount);
        }
        // Unlocked tranche receives the share token now; locked tranche is only recorded
        // (delivered off-chain at maturity) via the Claimed event. A zero share token is only
        // valid for the locked tranche.
        if (tranche == TRANCHE_UNLOCKED) {
            require(_shareToken != address(0), "Share token required");
            if (_tokenAmount > 0) {
                IERC20(_shareToken).safeTransfer(_account, _tokenAmount);
            }
        }

        emit Claimed(_saleId, _account, _refundAmount, _shareToken, _tokenAmount, tranche);
    }

    /// @dev Read-only preview of what claim() would do for the given leaf inputs, without changing
    ///      state. Mirrors claim()'s validation and delivery routing.
    /// @return valid True if the sale is finalized and the proof matches the leaf
    /// @return alreadyClaimed True if the account has already claimed
    /// @return tranche The account's locked tranche (0 = never deposited)
    /// @return sendShares True if a successful claim would transfer the share token now
    ///         (unlocked tranche, non-zero amount and share token)
    function previewClaim(
        uint64 _saleId,
        address _account,
        uint256 _refundAmount,
        address _shareToken,
        uint256 _tokenAmount,
        bytes32[] calldata _proof
    ) external view returns (bool valid, bool alreadyClaimed, uint8 tranche, bool sendShares) {
        bytes32 leaf =
            keccak256(abi.encode(block.chainid, _saleId, _account, _refundAmount, _shareToken, _tokenAmount));
        bytes32 root = settlements[_saleId].root;
        valid = root != bytes32(0) && MerkleProof.verifyCalldata(_proof, root, leaf);
        alreadyClaimed = claimed[_saleId][_account];
        tranche = userTranche[_saleId][_account];
        sendShares =
            valid && !alreadyClaimed && tranche == TRANCHE_UNLOCKED && _shareToken != address(0) && _tokenAmount > 0;
    }

    /// @dev Update the review window between set and finalize (min 6h).
    function setWaitingPeriod(uint256 _waitingPeriod) external onlyRole(MANAGER) {
        require(_waitingPeriod >= 6 hours, "Waiting period too short");
        waitingPeriod = _waitingPeriod;
        emit WaitingPeriodUpdated(_waitingPeriod);
    }

    /// @dev Manager (multisig) safety valve; there is no normal withdrawal path.
    ///      WARNING: this does NOT adjust any internal accounting (totalDeposits, pubTotalDeposits,
    ///      settlement totals). Withdrawing the deposit token can leave the contract without enough
    ///      balance to satisfy outstanding refunds, causing finalized claims to revert and stranding
    ///      those refunds. After using it, the tracked totals must be restaged (or the contract
    ///      upgraded) before normal claims can resume. Use only in emergencies.
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
