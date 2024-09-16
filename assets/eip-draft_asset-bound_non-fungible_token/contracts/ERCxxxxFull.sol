// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./ERCxxxx.sol";
import "./IERCxxxxAttestationLimited.sol";
import "./IERCxxxxFloatable.sol";
import "./IERCxxxxLockable.sol";

contract ERCxxxxFull is ERCxxxx, IERCxxxxAttestationLimited, IERCxxxxFloatable, IERCxxxxLockable {

    uint8 canStartFloatingMap;
    uint8 canStopFloatingMap;

    /// ###############################################################################################################################
    /// ##############################################################################################  IERCxxxxLockable
    /// ###############################################################################################################################
    mapping (uint256 => uint256) public lockCount;
    mapping (uint256 => uint256) public lienCount;
    mapping (uint256 => mapping (address => bool)) public tokenLocks;
    mapping (uint256 => mapping (address => bool)) public tokenLiens;
    
    function addLock(uint256 tokenId) public {
        require(!tokenLocks[tokenId][msg.sender], "ERCxxxxLockable: caller has already added a lock for this token");
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERCxxxxLockable: Caller is not owner nor approved to operate the token");

        tokenLocks[tokenId][msg.sender] = true;
        lockCount[tokenId]++;

        emit AnchorLockAdded(anchorByToken[tokenId], msg.sender, lockCount[tokenId]);
    }
    
    function removeLock(uint256 tokenId) public {
        require(tokenLocks[tokenId][msg.sender], "ERCxxxxLockable: caller has not added a lock for this token");

        tokenLocks[tokenId][msg.sender] = false;
        lockCount[tokenId]--;

        emit AnchorLockRemoved(anchorByToken[tokenId], msg.sender, lockCount[tokenId]);
    }

    function addLien(uint256 tokenId) public {
        require(!tokenLiens[tokenId][msg.sender], "ERCxxxxLockable: caller has already added a lock for this token");
        require(_isApprovedOrOwner(msg.sender, tokenId), "ERCxxxxLockable: Caller is not owner nor approved to operate the token");

        tokenLiens[tokenId][msg.sender] = true;
        lienCount[tokenId]++;

        emit AnchorLienAdded(anchorByToken[tokenId], msg.sender, lienCount[tokenId]);
    }

    function removeLien(uint256 tokenId) public {
        require(tokenLiens[tokenId][msg.sender], "ERCxxxxLockable: caller has not added a lien for this token");

        tokenLiens[tokenId][msg.sender] = false;
        lienCount[tokenId]--;

        emit AnchorLienRemoved(anchorByToken[tokenId], msg.sender, lienCount[tokenId]);
    }

    function anchorIsLocked(bytes32 anchor) public view returns (bool) {
        return lockCount[tokenByAnchor[anchor]] > 0;
    }

    function anchorHasLien(bytes32 anchor) public view returns (bool) {
        return lienCount[tokenByAnchor[anchor]] > 0;
    }

    function tokenIsLocked(uint256 tokenId) public view returns (bool) {
        return lockCount[tokenId] > 0;
    }

    function tokenHasLien(uint256 tokenId) public view returns (bool) {
        return lienCount[tokenId] > 0;
    }

    /// ###############################################################################################################################
    /// ##############################################################################################  IERCxxxxAttestedTransferLimited
    /// ###############################################################################################################################
    
    mapping(bytes32 => uint256) attestedTransferLimitByAnchor;
    
    uint256 public globalAttestedTransferLimitByAnchor;
    AttestedTransferLimitUpdatePolicy public transferLimitPolicy;

    /// @dev Counts the number of attested transfers by Anchor
    bool public canFloat; // Indicates whether tokens can "float" in general, i.e. be transferred without attestation
    bool public allFloating;

    function requireValidLimitUpdate(uint256 oldValue, uint256 newValue) internal view {
        if(newValue > oldValue) {
            require(transferLimitPolicy == AttestedTransferLimitUpdatePolicy.FLEXIBLE || transferLimitPolicy == AttestedTransferLimitUpdatePolicy.INCREASE_ONLY, "EIP-xxxx: Updating attestedTransferLimit violates policy");
        } else {
            require(transferLimitPolicy == AttestedTransferLimitUpdatePolicy.FLEXIBLE || transferLimitPolicy == AttestedTransferLimitUpdatePolicy.DECREASE_ONLY, "EIP-xxxx: Updating attestedTransferLimit violates policy");
        }
    }

    function updateGlobalAttestedTransferLimit(uint256 _nrTransfers) 
        public 
        onlyRole(MAINTAINER_ROLE) 
    {
       requireValidLimitUpdate(globalAttestedTransferLimitByAnchor, _nrTransfers);
       globalAttestedTransferLimitByAnchor = _nrTransfers;
       emit GlobalAttestedTransferLimitUpdate(_nrTransfers, msg.sender);
    }

    function updateAttestedTransferLimit(bytes32 anchor, uint256 _nrTransfers) 
        public 
        onlyRole(MAINTAINER_ROLE) 
    {
       uint256 currentLimit = attestedTransferLimit(anchor);
       requireValidLimitUpdate(currentLimit, _nrTransfers);
       attestedTransferLimitByAnchor[anchor] = _nrTransfers;
       emit AttestedTransferLimitUpdate(_nrTransfers, anchor, msg.sender);
    }

    function attestedTransferLimit(bytes32 anchor) public view returns (uint256 limit) {
        if(attestedTransferLimitByAnchor[anchor] > 0) { // Per anchor overwrites always, even if smaller than globalAttestedTransferLimit
            return attestedTransferLimitByAnchor[anchor];
        } 
        return globalAttestedTransferLimitByAnchor;
    }

    function attestatedTransfersLeft(bytes32 anchor) public view returns (uint256 nrTransfersLeft) {
        // FIXME panics when attestationsUsedByAnchor > attestedTransferLimit 
        // since this should never happen, maybe ok?
        return attestedTransferLimit(anchor) - attestationsUsedByAnchor[anchor];
    }

    /// ###############################################################################################################################
    /// ##############################################################################################  FLOATABILITY
    /// ###############################################################################################################################
    function canStartFloating(ERCxxxxAuthorization op) public
        floatable()
        onlyRole(MAINTAINER_ROLE)
     {
        canStartFloatingMap = createAuthorizationMap(op);
        emit CanStartFloating(op, msg.sender);

    }
        
    function canStopFloating(ERCxxxxAuthorization op) public
        floatable()
        onlyRole(MAINTAINER_ROLE) {
        canStopFloatingMap = createAuthorizationMap(op);
        emit CanStopFloating(op, msg.sender);
    }

    modifier floatable() {
        require(canFloat, "ERC-XXXX: Tokens not floatable");
        _;
    }      

    function allowFloating(bytes32 anchor, bool _doFloat)    
     public 
     {        
        if(_doFloat) {
            require(roleBasedAuthorization(anchor, canStartFloatingMap), "ERC-XXXX: No permission to start floating");
        } else {
            require(roleBasedAuthorization(anchor, canStopFloatingMap), "ERC-XXXX: No permission to stop floating");
        }

        require(_doFloat != isFloating(anchor), "EIP-XXXX: allowFloating can only be called when changing floating state");
        anchorIsReleased[anchor] = _doFloat;
        emit AnchorFloatingState(anchor, tokenByAnchor[anchor], _doFloat);
    }

    function _beforeAttestationIsUsed(bytes32 anchor, address to) internal view virtual override(ERCxxxx) {
        // empty, can be overwritten by derived conctracts.
        require(attestatedTransfersLeft(anchor) > 0, "ERC-XXXX: No attested transfers left");

        // Locks prevent use of attestation. Liens dont.
        require(!anchorIsLocked(anchor), "ERC-XXXX: Anchor is locked, attestation can't transfer.");

        super._beforeAttestationIsUsed(anchor, to);
    }

    function isFloating(bytes32 anchor) public view returns (bool){
        return anchorIsReleased[anchor];
    }    

    constructor(
        string memory _name, 
        string memory _symbol, 
        ERCxxxxAuthorization _burnAuth, 
        ERCxxxxAuthorization _approveAuth, 
        bool _canFloat, 
        uint256 attestationLimitPerAnchor,
        AttestedTransferLimitUpdatePolicy _limitUpdatePolicy)
        ERCxxxx(_name, _symbol, _burnAuth, _approveAuth) {          
            canFloat = _canFloat;
            transferLimitPolicy = _limitUpdatePolicy;
            globalAttestedTransferLimitByAnchor = attestationLimitPerAnchor;
            // TODO Parameter for "Float by default, i.e. each minted anchor is floating"
    }
}
