// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PendingReceiptNFT {
    error Unauthorized();
    error AdapterAlreadySet();
    error TokenNotFound(uint256 tokenId);
    error AlreadySettled(uint256 tokenId);
    error NotSettledBeforeBurn(uint256 tokenId);
    error InvalidRecipient();

    address public adapter;
    address public owner;

    uint256 private _nextTokenId = 1;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    struct ReceiptData {
        bytes32 productId;
        uint256 amount;
        address originalDepositor;
        uint256 dispatchBlock;
        bool settled;
    }

    mapping(uint256 => ReceiptData) public receipts;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    event AdapterSet(address indexed adapter);
    event ReceiptMinted(uint256 indexed tokenId, address indexed to, bytes32 indexed productId, uint256 amount);
    event ReceiptSettled(uint256 indexed tokenId, address indexed finalHolder);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyAdapter() {
        if (msg.sender != adapter) revert Unauthorized();
        if (adapter == address(0)) revert Unauthorized();
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

    function mint(address to, ReceiptData calldata data) external onlyAdapter returns (uint256) {
        if (to == address(0)) revert InvalidRecipient();

        uint256 tokenId = _nextTokenId++;

        _owners[tokenId] = to;
        _balances[to]++;
        receipts[tokenId] = data;

        emit Transfer(address(0), to, tokenId);
        emit ReceiptMinted(tokenId, to, data.productId, data.amount);

        return tokenId;
    }

    function burn(uint256 tokenId) external onlyAdapter {
        if (!_exists(tokenId)) revert TokenNotFound(tokenId);
        if (!receipts[tokenId].settled) revert NotSettledBeforeBurn(tokenId);

        address currentOwner = ownerOf(tokenId);

        delete _owners[tokenId];
        _balances[currentOwner]--;
        delete _tokenApprovals[tokenId];

        emit Transfer(currentOwner, address(0), tokenId);
        emit ReceiptSettled(tokenId, currentOwner);
    }

    function markSettled(uint256 tokenId) external onlyAdapter {
        if (!_exists(tokenId)) revert TokenNotFound(tokenId);
        if (receipts[tokenId].settled) revert AlreadySettled(tokenId);
        receipts[tokenId].settled = true;
    }

    function isSettled(uint256 tokenId) external view returns (bool) {
        return receipts[tokenId].settled;
    }

    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    // ERC-721 Interface
    function balanceOf(address tokenOwner) public view returns (uint256) {
        if (tokenOwner == address(0)) revert InvalidRecipient();
        return _balances[tokenOwner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert TokenNotFound(tokenId);
        return tokenOwner;
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert Unauthorized();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory /* data */ ) public {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert Unauthorized();
        _transfer(from, to, tokenId);
        // Note: safeTransferFrom usually checks onERC721Received for contract receivers.
        // For simplicity in this spec, we just transfer. If strict ERC721 safety is needed, it can be added.
    }

    function approve(address to, uint256 tokenId) public {
        address tokenOwner = ownerOf(tokenId);
        if (to == tokenOwner) revert InvalidRecipient();
        if (msg.sender != tokenOwner && !isApprovedForAll(tokenOwner, msg.sender)) revert Unauthorized();

        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public {
        if (operator == msg.sender) revert InvalidRecipient();
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        if (!_exists(tokenId)) revert TokenNotFound(tokenId);
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address tokenOwner, address operator) public view returns (bool) {
        return _operatorApprovals[tokenOwner][operator];
    }

    // Helpers
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return (spender == tokenOwner || getApproved(tokenId) == spender || isApprovedForAll(tokenOwner, spender));
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        if (ownerOf(tokenId) != from) revert Unauthorized();
        if (to == address(0)) revert InvalidRecipient();

        delete _tokenApprovals[tokenId];
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }
}
