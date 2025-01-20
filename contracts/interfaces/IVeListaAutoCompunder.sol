// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IVeListaAutoCompounder {
    function enableAutoCompound() external;
    function disableAutoCompound() external;
    function isAutoCompoundEnabled(address account) external view returns (bool);
}
