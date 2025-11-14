// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
    @title Mock ERC20 Token
 */
contract MockERC20 is ERC20, Ownable {
    address public minter;

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

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

}
