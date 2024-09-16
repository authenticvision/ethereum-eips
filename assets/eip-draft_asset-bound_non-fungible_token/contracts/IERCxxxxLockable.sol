// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./IERCxxxx.sol";

interface IERCxxxxLockable is IERCxxxx {
    
    function addLock(uint256 tokenId) external;
    function removeLock(uint256 tokenId) external;

    function addLien(uint256 tokenId) external;
    function removeLien(uint256 tokenId) external;

    function anchorIsLocked(bytes32 anchor) external view returns (bool);
    function anchorHasLien(bytes32 anchor) external view returns (bool);

    function tokenIsLocked(uint256 tokenId) external view returns (bool);
    function tokenHasLien(uint256 tokenId) external view returns (bool);

    event AnchorLockAdded(
        bytes32 indexed anchor,
        address indexed lockingAccount,
        uint256 indexed lockCount
    );

    event AnchorLockRemoved(
        bytes32 indexed anchor,
        address indexed lockingAccount,
        uint256 indexed lockCount
    );

    event AnchorLienAdded(
        bytes32 indexed anchor,
        address indexed lienAccount,
        uint256 indexed lienCount
    );

    event AnchorLienRemoved(
        bytes32 indexed anchor,
        address indexed lienAccount,
        uint256 indexed lienCount
    );
}