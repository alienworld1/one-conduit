// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IERC20.sol";

contract EscrowVault {
    error Unauthorized();
    error AdapterAlreadySet();
    error EscrowAlreadyExists(uint256 receiptId);
    error EscrowNotFound(uint256 receiptId);
    error AlreadyReleased(uint256 receiptId);

    address public adapter; // XCMAdapter — set post-deploy via setAdapter()
    address public owner; // deployer, for setAdapter() only

    struct Escrow {
        address token; // the token being held (DOT or mock token)
        uint256 amount; // amount deposited
        bool released; // guard against double-release
    }

    mapping(uint256 => Escrow) private escrows; // receiptId → escrow record

    event AdapterSet(address indexed adapter);
    event Deposited(uint256 indexed receiptId, address token, uint256 amount);
    event Released(uint256 indexed receiptId, address indexed to, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyAdapter() {
        if (msg.sender != adapter) revert Unauthorized();
        if (adapter == address(0)) revert Unauthorized(); // extra safety before setAdapter called
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function setAdapter(address adapter_) external onlyOwner {
        if (adapter != address(0)) revert AdapterAlreadySet();
        adapter = adapter_;
        emit AdapterSet(adapter_);
    }

    function deposit(uint256 receiptId, address token, uint256 amount) external onlyAdapter {
        if (escrows[receiptId].amount != 0) revert EscrowAlreadyExists(receiptId);

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        escrows[receiptId] = Escrow(token, amount, false);

        emit Deposited(receiptId, token, amount);
    }

    function release(uint256 receiptId, address to) external onlyAdapter {
        Escrow memory escrow = escrows[receiptId];
        if (escrow.amount == 0) revert EscrowNotFound(receiptId);
        if (escrow.released) revert AlreadyReleased(receiptId);

        escrows[receiptId].released = true;
        IERC20(escrow.token).transfer(to, escrow.amount);

        emit Released(receiptId, to, escrow.amount);
    }

    function getBalance(uint256 receiptId) external view returns (uint256) {
        return escrows[receiptId].amount;
    }

    function getEscrow(uint256 receiptId) external view returns (Escrow memory) {
        return escrows[receiptId];
    }
}
