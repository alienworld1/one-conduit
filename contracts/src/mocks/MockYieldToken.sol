// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*
 * MockYieldToken — ERC-20 yield token issued by MockLendingPool.
 * 6 decimals — matches the underlying token to avoid share math precision issues.
 * Only the pool (set at deploy time) can mint or burn.
 * Freely transferable — holders can sell their yield position like a real aToken.
 * No OpenZeppelin — inline implementation to keep PVM compilation simple.
 */
contract MockYieldToken {
    string  public name;
    string  public symbol;
    uint8   public constant decimals = 6;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public pool; // only the pool may mint or burn

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner_, address indexed spender, uint256 value);

    modifier onlyPool() {
        require(msg.sender == pool, "not pool");
        _;
    }

    constructor(string memory name_, string memory symbol_, address pool_) {
        name   = name_;
        symbol = symbol_;
        pool   = pool_;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "ERC20: insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to]         += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from]             >= amount, "ERC20: insufficient balance");
        require(allowance[from][msg.sender] >= amount, "ERC20: insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from]             -= amount;
        balanceOf[to]               += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function mint(address to, uint256 amount) external onlyPool {
        totalSupply   += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyPool {
        require(balanceOf[from] >= amount, "ERC20: insufficient balance");
        totalSupply       -= amount;
        balanceOf[from]   -= amount;
        emit Transfer(from, address(0), amount);
    }
}
