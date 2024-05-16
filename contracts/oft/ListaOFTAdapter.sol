// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";

/**
  * @title Lista OFTAdapter Contract
  * @dev Lista OFTAdapter is a contract that adapts the ListaToken to the OFT functionality.
    User's are can transfer their lista token by lock their tokens into this contract,
    and receive the 1:1 backed token on the other chain.
  */
contract ListaOFTAdapter is OFTAdapter {

  /**
    * @dev Constructor for the ListaAdapter contract
    * @param _token An ERC20 token address that has already been deployed and exists.
    * @param _lzEndpoint The address of the LayerZero endpoint
    * @param _owner The address of the owner of the contract
    */
  constructor (
    address _token,
    address _lzEndpoint,
    address _owner
  ) OFTAdapter(_token, _lzEndpoint, _owner) {}

}
