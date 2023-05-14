// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./ERC6956.sol";
import "./IERC6956AttestationLimited.sol";
import "./IERC6956Floatable.sol";
import "./IERC6956ValidAnchors.sol";

/**
 * @title 
 * @author 
 * @notice 
 * 
 * @dev Error-codes
 * ERROR | Message
 * ------|-------------------------------------------------------------------
 * E1-20 | See ERC6956.sol
 * E21   | No permission to start floating
 * E22   | No permission to stop floating
 * E23   | allowFloating can only be called when changing floating state
 * E24   | No attested transfers left
 * E25   | data must contain merkle-proof
 * E26   | Anchor not valid
 */
contract ERC6956Full is ERC6956, IERC6956AttestationLimited, IERC6956Floatable, IERC6956ValidAnchors {

    uint8 private _canStartFloatingMap;
    uint8 private _canStopFloatingMap;

    /// ###############################################################################################################################
    /// ##############################################################################################  IERC6956AttestedTransferLimited
    /// ###############################################################################################################################
    
    mapping(bytes32 => uint256) public attestedTransferLimitByAnchor;
    
    uint256 public globalAttestedTransferLimitByAnchor;
    AttestationLimitUpdatePolicy public transferLimitPolicy;

    /// @dev Counts the number of attested transfers by Anchor
    bool public canFloat; // Indicates whether tokens can "float" in general, i.e. be transferred without attestation
    bool public allFloating;
    bool public floatingByDefault;

    /// @dev The merkle-tree root node, where proof is validated against. Update via updateValidAnchors(). Use salt-leafs in merkle-trees!
    bytes32 private _validAnchorsMerkleRoot;

    function _requireValidLimitUpdate(uint256 oldValue, uint256 newValue) internal view {
        if(newValue > oldValue) {
            require(transferLimitPolicy == AttestationLimitUpdatePolicy.FLEXIBLE || transferLimitPolicy == AttestationLimitUpdatePolicy.INCREASE_ONLY, "EIP-6956: Updating attestedTransferLimit violates policy");
        } else {
            require(transferLimitPolicy == AttestationLimitUpdatePolicy.FLEXIBLE || transferLimitPolicy == AttestationLimitUpdatePolicy.DECREASE_ONLY, "EIP-6956: Updating attestedTransferLimit violates policy");
        }
    }

    function _afterAnchorMint(address /*to*/, bytes32 anchor, uint256 /*tokenId*/) internal override(ERC6956) virtual {
        _allowFloating(anchor, floatingByDefault);        
    }

    function updateAnchorFloatingByDefault(bool _floatsByDefault) public 
    onlyMaintainer() {
        floatingByDefault = true;
        emit DefaultFloatingStateChange(_floatsByDefault, msg.sender);      
    }

    function updateGlobalAttestationLimit(uint256 _nrTransfers) 
        public 
        onlyMaintainer() 
    {
       _requireValidLimitUpdate(globalAttestedTransferLimitByAnchor, _nrTransfers);
       globalAttestedTransferLimitByAnchor = _nrTransfers;
       emit GlobalAttestationLimitUpdate(_nrTransfers, msg.sender);
    }

    function updateAttestationLimit(bytes32 anchor, uint256 _nrTransfers) 
        public 
        onlyMaintainer() 
    {
       uint256 currentLimit = attestedTransferLimit(anchor);
       _requireValidLimitUpdate(currentLimit, _nrTransfers);
       attestedTransferLimitByAnchor[anchor] = _nrTransfers;
       emit AttestationLimitUpdate(anchor, tokenByAnchor[anchor], _nrTransfers, msg.sender);
    }

    function attestedTransferLimit(bytes32 anchor) public view returns (uint256 limit) {
        if(attestedTransferLimitByAnchor[anchor] > 0) { // Per anchor overwrites always, even if smaller than globalAttestedTransferLimit
            return attestedTransferLimitByAnchor[anchor];
        } 
        return globalAttestedTransferLimitByAnchor;
    }

    function attestationUsagesLeft(bytes32 anchor) public view returns (uint256 nrTransfersLeft) {
        // FIXME panics when attestationsUsedByAnchor > attestedTransferLimit 
        // since this should never happen, maybe ok?
        return attestedTransferLimit(anchor) - attestationsUsedByAnchor[anchor];
    }

    /// ###############################################################################################################################
    /// ##############################################################################################  FLOATABILITY
    /// ###############################################################################################################################
    function canStartFloating(ERC6956Authorization op) public
        onlyMaintainer() {
        _canStartFloatingMap = createAuthorizationMap(op);
        emit CanStartFloating(op, msg.sender);
    }
        
    function canStopFloating(ERC6956Authorization op) public
        onlyMaintainer() {
        _canStopFloatingMap = createAuthorizationMap(op);
        emit CanStopFloating(op, msg.sender);
    } 

    function _allowFloating(bytes32 anchor, bool _doFloat) internal {
        anchorIsReleased[anchor] = _doFloat;
        emit AnchorFloatingStateChange(anchor, tokenByAnchor[anchor], _doFloat);
    }

    function allowFloating(bytes32 anchor, bool _doFloat)    
     public 
     {        
        if(_doFloat) {
            require(_roleBasedAuthorization(anchor, _canStartFloatingMap), "ERC6956-E21");
        } else {
            require(_roleBasedAuthorization(anchor, _canStopFloatingMap), "ERC6956-E22");
        }

        require(_doFloat != isFloating(anchor), "ERC6956-E23");
        _allowFloating(anchor, _doFloat);        
    }

    function _beforeAttestationIsUsed(bytes32 anchor, address to, bytes memory data) internal view virtual override(ERC6956) {
        // empty, can be overwritten by derived conctracts.
        require(attestationUsagesLeft(anchor) > 0, "ERC6956-E24");

        // IERC6956ValidAnchors check anchor is indeed valid in contract
        require(data.length > 0, "ERC6956-E25");
        bytes32[] memory proof;
        (proof) = abi.decode(data, (bytes32[])); // Decode it with potentially more data following. If there is more data, this may be passed on to safeTransfer
        require(validAnchor(anchor, proof), "ERC6956-E26");

        super._beforeAttestationIsUsed(anchor, to, data);
    }


    /// @notice Update the Merkle root containing the valid anchors. Consider salt-leaves!
    /// @dev Proof (transferAnchor) needs to be provided from this tree. 
    /// @dev The merkle-tree needs to contain at least one "salt leaf" in order to not publish the complete merkle-tree when all anchors should have been dropped at least once. 
    /// @param merkleRootNode The root, containing all anchors we want validated.
    function updateValidAnchors(bytes32 merkleRootNode) public onlyMaintainer() {
        _validAnchorsMerkleRoot = merkleRootNode;
        emit ValidAnchorsUpdate(merkleRootNode, msg.sender);
    }

    function validAnchor(bytes32 anchor, bytes32[] memory proof) public view returns (bool) {
        return MerkleProof.verify(
            proof,
            _validAnchorsMerkleRoot,
            keccak256(bytes.concat(keccak256(abi.encode(anchor)))));
    }

    function isFloating(bytes32 anchor) public view returns (bool){
        return anchorIsReleased[anchor];
    }    

    constructor(
        string memory _name, 
        string memory _symbol, 
        AttestationLimitUpdatePolicy _limitUpdatePolicy)
        ERC6956(_name, _symbol) {          
            transferLimitPolicy = _limitUpdatePolicy;

        // Note per default no-one change floatability. canStartFloating and canStopFloating needs to be configured first!        
    }
}
