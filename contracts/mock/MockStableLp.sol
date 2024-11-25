// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PancakeStableSwapLP is ERC20 {
    address public minter;
    address public owner;

    constructor() ERC20("Pancake StableSwap LPs", "Stable-LP") {
        minter = msg.sender;
        owner = msg.sender;
    }

    /**
     * @notice Checks if the msg.sender is the minter address.
     */
    modifier onlyMinter() {
        require(msg.sender == minter, "Not minter");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not minter");
        _;
    }

    modifier onlyMinterOrOwner() {
        require(msg.sender == owner || msg.sender == minter, "Not owner or minter");
        _;
    }

    function setOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;
    }

    function setMinter(address _newMinter) external onlyMinterOrOwner {
        minter = _newMinter;
    }

    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }

    function burnFrom(address _to, uint256 _amount) external onlyMinter {
        _burn(_to, _amount);
    }
}