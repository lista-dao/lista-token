// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// @notice An alternative version of the openzeppelin Pausable contract
abstract contract PausableAlt is Pausable, Ownable {

  // an multi-sig address to pause the transferal function in emergency
  address public multiSig;

  /**
   * @dev Modifier to make a function callable only when the caller equals to the multiSig address.
   */
  modifier isMultiSig() {
    require(multiSig != address(0), "PausableAlt: multiSig not set");
    require(msg.sender == multiSig, "PausableAlt: not multiSig");
    _;
  }

  event MultiSigUpdated(address oldMultiSig, address newMultiSig);

  function setMultiSig(address _multiSig) external onlyOwner {
    address oldMultiSig = multiSig;
    multiSig = _multiSig;
    emit MultiSigUpdated(oldMultiSig, _multiSig);
  }

  function pause() external isMultiSig {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

}
