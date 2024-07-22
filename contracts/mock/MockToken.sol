// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
  constructor(
    address owner,
    string memory _name,
    string memory _symbol
  ) ERC20(_name, _symbol) {
    // mint 1B tokens to the lista treasury account
    _mint(owner, 1_000_000_000 * 10 ** decimals());
  }

}
