// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./IERC6956.sol";

interface IERC6956Floatable is IERC6956 {

    function updateFloatingAuthorization(ERC6956Authorization startFloatingAuthorization, ERC6956Authorization stopFloatingAuthorization) external;

    function float(bytes32 anchor, bool _doFloat) external;
    function floatAll(bool allFloating) external;

    function floating(bytes32 anchor) external view returns (bool);

    event FloatingStateChange(bytes32 indexed anchor, uint256 indexed tokenId, bool isFloating, address operator);
    event FloatingAuthorizationChange(ERC6956Authorization startAuthorization, ERC6956Authorization stopAuthorization, address maintainer);
    event FloatingAllStateChange(bool areFloating, address operator);
}