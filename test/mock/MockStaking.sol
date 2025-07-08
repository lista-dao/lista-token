// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract MockStaking {
    struct Pool {
        address lpToken;
        address rewardToken;
        address poolAddress;
        address distributor;
        bool isActive;
    }

    mapping(address => Pool) public pools;

    function deposit(address pool, uint256 amount) external {
        IERC20(pools[pool].lpToken).transferFrom(msg.sender, address(this), amount);
    }

    function harvest(address pool) external returns (uint256) {
        return 0;
    }

    function withdraw(address to, address pool, uint256 amount) external {
        IERC20(pools[pool].lpToken).transfer(to, amount);
    }

    function registerPool(
        address lpToken,
        address rewardToken,
        address poolAddress,
        address distributor
    ) external {
        pools[lpToken] = Pool(lpToken, rewardToken, poolAddress, distributor, true);
    }

    function unregisterPool(address lpToken) external {
        delete pools[lpToken];
    }

}
