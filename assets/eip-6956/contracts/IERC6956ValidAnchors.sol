// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./IERC6956.sol";

/**
 * @title Anchor-validating Asset-Bound NFT
 * @dev See https://eips.ethereum.org/EIPS/eip-6956
 *      Note: The ERC-165 identifier for this interface is 0x051c9bd8
 */
interface IERC6956ValidAnchors is IERC6956 {

    event ValidAnchorsUpdate(bytes32 indexed validAnchorHash, address indexed maintainer);

    function anchorValid(bytes32 anchor, bytes32[] memory proof) external view returns (bool isValid);        
}