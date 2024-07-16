// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
    @title Mock ERC20 Token
 */
contract MockERC20 is ERC20, Ownable {
    constructor(address owner, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        require(owner != address(0), "owner is the zero address");
        _transferOwnership(owner);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
