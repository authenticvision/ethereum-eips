// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "./IERC6956.sol";

/**
 * @title Floatable Asset-Bound NFT
 * @notice A floatable Asset-Bound NFT can (temporarily) be transferred without attestation
 * @dev See https://eips.ethereum.org/EIPS/eip-6956
 *      Note: The ERC-165 identifier for this interface is 0xdfd691a6
 */
interface IERC6956Floatable is IERC6956 {

    enum FloatState {
        Default, // 0, inherits from floatAll
        Floating, // 1
        Anchored // 2
    }

    function floating(bytes32 anchor) external view returns (bool);
    function floatStartAuthorization() external view returns (Authorization canStartFloating);
    function floatStopAuthorization() external view returns (Authorization canStartFloating);


    function float(bytes32 anchor, FloatState newState) external;
    function floatAll(bool allFloating) external; // true ... FloatState.Floating, false ... FloatState.Anchored
   

    event FloatingStateChange(bytes32 indexed anchor, uint256 indexed tokenId, bool isFloating, address operator);
    event FloatingAuthorizationChange(Authorization startAuthorization, Authorization stopAuthorization, address maintainer);
    event FloatingAllStateChange(bool areFloating, address operator);
}