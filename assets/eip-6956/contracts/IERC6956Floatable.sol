// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./IERC6956.sol";

interface IERC6956Floatable is IERC6956 {

    enum FloatState {
        Default, // 0, inherits from floatAll
        Floating, // 1
        Anchored // 2
    }

    function updateFloatingAuthorization(Authorization startFloatingAuthorization, Authorization stopFloatingAuthorization) external;

    function float(bytes32 anchor, FloatState newState) external;
    function floatAll(bool allFloating) external; // true ... FloatState.Floating, false ... FloatState.Anchored

    function floating(bytes32 anchor) external view returns (bool);

    event FloatingStateChange(bytes32 indexed anchor, uint256 indexed tokenId, bool isFloating, address operator);
    event FloatingAuthorizationChange(Authorization startAuthorization, Authorization stopAuthorization, address maintainer);
    event FloatingAllStateChange(bool areFloating, address operator);
}