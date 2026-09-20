// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ILockToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Irrevocable deposits, withdrawable by their beneficiary at or after unlockTime.
/// @dev Designed exclusively for the exact-transfer Lock token shipped with this project.
contract TimeLock {
    struct Deposit {
        address depositor;
        address beneficiary;
        uint256 amount;
        uint256 unlockTime;
        bool withdrawn;
    }

    ILockToken public immutable token;
    uint256 public nextLockId;
    uint256 public totalLocked;
    mapping(uint256 => Deposit) private deposits;
    mapping(address => uint256[]) private beneficiaryLocks;
    bool private entered;

    error InvalidToken();
    error InvalidBeneficiary();
    error InvalidAmount();
    error InvalidUnlockTime();
    error UnknownLock();
    error NotBeneficiary();
    error AlreadyWithdrawn();
    error StillLocked();
    error TransferFailed();
    error Reentrancy();

    event Locked(
        uint256 indexed lockId,
        address indexed depositor,
        address indexed beneficiary,
        uint256 amount,
        uint256 unlockTime
    );
    event LockExtended(uint256 indexed lockId, uint256 previousUnlockTime, uint256 unlockTime);
    event Withdrawn(uint256 indexed lockId, address indexed beneficiary, uint256 amount);

    constructor(address token_) {
        if (token_.code.length == 0) revert InvalidToken();
        token = ILockToken(token_);
    }

    modifier nonReentrant() {
        if (entered) revert Reentrancy();
        entered = true;
        _;
        entered = false;
    }

    /// @notice Pulls tokens from the caller; approval is required before depositing.
    function lock(address beneficiary, uint256 amount, uint256 unlockTime)
        external
        nonReentrant
        returns (uint256 lockId)
    {
        if (beneficiary == address(0) || beneficiary == address(this)) revert InvalidBeneficiary();
        if (amount == 0) revert InvalidAmount();
        if (unlockTime <= block.timestamp) revert InvalidUnlockTime();

        lockId = nextLockId++;
        deposits[lockId] = Deposit(msg.sender, beneficiary, amount, unlockTime, false);
        beneficiaryLocks[beneficiary].push(lockId);
        totalLocked += amount;
        emit Locked(lockId, msg.sender, beneficiary, amount, unlockTime);
        if (!token.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
    }

    /// @notice Only the beneficiary can voluntarily delay an unwithdrawn lock, even after maturity.
    function extendLock(uint256 lockId, uint256 unlockTime) external nonReentrant {
        Deposit storage deposit = _ownedLock(lockId);
        if (unlockTime <= deposit.unlockTime || unlockTime <= block.timestamp) revert InvalidUnlockTime();
        uint256 previousUnlockTime = deposit.unlockTime;
        deposit.unlockTime = unlockTime;
        emit LockExtended(lockId, previousUnlockTime, unlockTime);
    }

    function withdraw(uint256 lockId) external nonReentrant {
        Deposit storage deposit = _ownedLock(lockId);
        if (block.timestamp < deposit.unlockTime) revert StillLocked();
        deposit.withdrawn = true;
        totalLocked -= deposit.amount;
        emit Withdrawn(lockId, deposit.beneficiary, deposit.amount);
        if (!token.transfer(deposit.beneficiary, deposit.amount)) revert TransferFailed();
    }

    function getLock(uint256 lockId) external view returns (Deposit memory) {
        if (lockId >= nextLockId) revert UnknownLock();
        return deposits[lockId];
    }

    /// @notice Counts all historical locks, including withdrawn locks, without an unbounded loop.
    function lockCount(address beneficiary) external view returns (uint256) {
        return beneficiaryLocks[beneficiary].length;
    }

    /// @notice Stable insertion-order enumeration; an out-of-range index reverts.
    function lockIdAt(address beneficiary, uint256 index) external view returns (uint256) {
        return beneficiaryLocks[beneficiary][index];
    }

    function _ownedLock(uint256 lockId) private view returns (Deposit storage deposit) {
        if (lockId >= nextLockId) revert UnknownLock();
        deposit = deposits[lockId];
        if (msg.sender != deposit.beneficiary) revert NotBeneficiary();
        if (deposit.withdrawn) revert AlreadyWithdrawn();
    }
}
