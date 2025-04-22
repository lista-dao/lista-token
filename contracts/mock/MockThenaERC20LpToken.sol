// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
    @title Mock Thena Gauge V2 staking token
 */
contract MockThenaERC20LpToken is ERC20, Ownable {
    address public minter;
    uint256 public total0;
    uint256 public total1;
    address public token0;
    address public token1;
    int24 public currentTick;

    constructor(address owner, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        require(owner != address(0), "owner is the zero address");
        _transferOwnership(owner);
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "only minter");
        _;
    }

    function mint(address to, uint256 amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }

    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    function getTotalAmounts() external view returns (uint256, uint256) {
        return (total0, total1);
    }

    function setTotalAmounts(uint256 _total0, uint256 _total1) external onlyOwner {
        total0 = _total0;
        total1 = _total1;
    }

    function setCurrentTick(int24 _currentTick) external onlyOwner {
        currentTick = _currentTick;
    }

    function setToken0(address _token0) external onlyOwner {
        token0 = _token0;
    }

    function setToken1(address _token1) external onlyOwner {
        token1 = _token1;
    }
}

