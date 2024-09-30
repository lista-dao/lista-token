pragma solidity ^0.8.10;

interface IPancakeStableSwapTwoPool {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external;
}