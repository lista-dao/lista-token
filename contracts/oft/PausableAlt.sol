// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// @notice An alternative version of the openzeppelin Pausable contract
abstract contract PausableAlt is Pausable, Ownable {

  // a multi-sig address to pause the transferal function in emergency
  address public multiSig;

  // @dev Modifier to make a function callable only when the caller equals to the multiSig address.
  modifier isMultiSig() {
    require(multiSig != address(0), "PausableAlt: multiSig not set");
    require(msg.sender == multiSig, "PausableAlt: not multiSig");
    _;
  }
  // @dev Emitted when the multiSig address is updated
  event MultiSigUpdated(address oldMultiSig, address newMultiSig);

  /**
   * @notice Set the multiSig address
   * @param _multiSig The new multiSig address
   */
  function setMultiSig(address _multiSig) external onlyOwner {
    require(multiSig != address(0), "PausableAlt: multiSig can't be zero address");
    require(multiSig != _multiSig, "PausableAlt: new multiSig needs to be different from the old one");
    address oldMultiSig = multiSig;
    multiSig = _multiSig;
    emit MultiSigUpdated(oldMultiSig, _multiSig);
  }

  /**
   * @notice Pause the contract
   */
  function pause() external isMultiSig {
    _pause();
  }

  /**
   * @notice Unpause the contract
   */
  function unpause() external onlyOwner {
    _unpause();
  }

}
