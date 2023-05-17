// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./IERC6956.sol";

interface IERC6956ValidAnchors is IERC6956 {

    event ValidAnchorsUpdate(bytes32 indexed validAnchorHash, address indexed maintainer);

    function anchorValid(bytes32 anchor, bytes32[] memory proof) external view returns (bool isValid);        
}