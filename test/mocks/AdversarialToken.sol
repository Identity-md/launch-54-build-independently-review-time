// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Test-only exact-transfer token with configurable faults and hostile callbacks.
contract AdversarialToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public mode; // 0 normal, 1 false, 2 revert, 3 empty return data
    address public target;
    bytes public callback;
    bool public callbackSucceeded;
    bytes public callbackResult;
    uint256 public callbackCount;
    error TokenDenied();

    constructor() {
        balanceOf[msg.sender] = 1e27;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function configure(uint256 mode_, address target_, bytes calldata callback_) external {
        mode = mode_;
        target = target_;
        callback = callback_;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        return _move(from, to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _move(msg.sender, to, amount);
    }

    function _move(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        if (target != address(0)) {
            ++callbackCount;
            (callbackSucceeded, callbackResult) = target.call(callback);
        }
        if (mode == 1) return false;
        if (mode == 2) revert TokenDenied();
        if (mode == 3) {
            assembly { return(0, 0) }
        }
        return true;
    }
}
