// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface ILpToken is IERC20 {
    function burn(address account, uint256 amount) external;

    function mint(address account, uint256 amount) external;

    function decimals() external view returns (uint8);
}
