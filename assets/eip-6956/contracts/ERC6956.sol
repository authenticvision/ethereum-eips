// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IERC6956.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

// TODO RENAME TO ERC6956 once granted, then derived contracts can say 'is ERC6956', when the reference
// implementation shall be used

/**
 * @title 
 * @author 
 * @notice 
 * 
 * @dev Error messages
 * ```
 * ERROR | Message
 * ------|-------------------------------------------------------------------
 * E1    | Only maintainer allowed
 * E2    | No permission to burn
 * E3    | Token does not exist, call transferAnchor first to mint
 * E4    | batchSize must be 1
 * E5    | Token not transferable
 * E6    | Token already owned
 * E7    | Not authorized
 * E8    | Attestation not signed by trusted oracle
 * E9    | Attestation already used
 * E10   | Attestation not valid yet
 * E11   | Attestation expired 
 * E12   | Attestation expired (contract limit)
 * E13   | Invalid signature length
 * E14-20| Reserved for future use
 * ```
 */
contract ERC6956 is
    ERC721,
    ERC721Enumerable,
    ERC721Burnable,
    IERC6956 
{
    using Counters for Counters.Counter;

    mapping(bytes32 => bool) public anchorIsReleased; // currently released anchors. Per default, all anchors are dropped, i.e. 1:1 bound
    
    mapping(address => bool) public maintainers;

    /// @notice Resolves tokenID to anchor. Inverse of tokenByAnchor
    mapping(uint256 => bytes32) public anchorByToken;

    /// @notice Resolves Anchor to tokenID. Inverse of anchorByToken
    mapping(bytes32 => uint256) public tokenByAnchor;

    mapping(address => bool) private _trustedOracles;

    /// @dev stores the anchors for each attestation
    // TODO the anchor is not really used.. can we save on gas if we store just an uint8?
    mapping(bytes32 => bytes32) private _anchorByUsedAttestation;

    /// @dev stores handed-back tokens (via burn)
    mapping (bytes32 => uint256) private _burnedTokensByAnchor;


     /**
     * @dev Counter to keep track of issued tokens
     */
    Counters.Counter private _tokenIdCounter;

    /// @dev Default validity timespan of attestation. In validateAttestation the attestationTime is checked for MIN(defaultAttestationvalidity, attestation.expiry)
    uint256 public maxAttestationExpireTime = 5*60; // 5min valid per default

    uint8 private _burnAuthorizationMap;
    uint8 private _approveAuthorizationMap;

/// @dev Records the number of transfers done for each attestation
    mapping(bytes32 => uint256) public attestationsUsedByAnchor;

    modifier onlyMaintainer() {
        require(isMaintainer(msg.sender), "ERC6956-E1");
        _;
    }

    /**
     * @notice Behaves like ERC721 burn() for wallet-cleaning purposes. Note only the tokenId (as a wrapper) is burned, not the ASSET represented by the ANCHOR.
     * @dev 
     * - tokenId is remembered for the anchor, to ensure a later transferAnchor(), which would mint, assigns the same tokenId. This ensures strict 1:1 relation
     * - For burning, the anchor needs to be released. This forced release FOR BURNING ONLY is allowed for owner() or approvedOwner().
     * 
     * @param tokenId The token that shall be burned
     */
    function burn(uint256 tokenId) public override
     {
        // remember the tokenId of burned tokens, s.t. one can issue the token with the same number again
        bytes32 anchor = anchorByToken[tokenId];
        require(_roleBasedAuthorization(anchor, _burnAuthorizationMap), "ERC6956-E2");
        _burn(tokenId);
    }

    function burnAnchor(bytes memory attestation, bytes memory data) public virtual
        authorized(ERC6956Role.ASSET, _burnAuthorizationMap)
     {
        address to;
        bytes32 anchor;
        bytes32 attestationHash;
        (to, anchor, attestationHash) = decodeAttestationIfValid(attestation, data);
        _commitAttestation(to, anchor, attestationHash);
        uint256 tokenId = tokenByAnchor[anchor];
        // remember the tokenId of burned tokens, s.t. one can issue the token with the same number again
        _burn(tokenId);
    }

    function burnAnchor(bytes memory attestation) public virtual {
        return burnAnchor(attestation, "");
    }

    function approveAnchor(bytes memory attestation, bytes memory data) public virtual 
        authorized(ERC6956Role.ASSET, _approveAuthorizationMap)
    {
        address to;
        bytes32 anchor;
        bytes32 attestationHash;
        (to, anchor, attestationHash) = decodeAttestationIfValid(attestation, data);
        _commitAttestation(to, anchor, attestationHash);
        require(tokenByAnchor[anchor]>0, "ERC6956-E3");
        _approve(to, tokenByAnchor[anchor]);
    }

    function approveAnchor(bytes memory attestation) public virtual {
        return approveAnchor(attestation, "");
    }
    
    function updateOracle(address _oracle, bool _trust) public
        onlyMaintainer() 
    {
        _trustedOracles[_oracle] = _trust;
        emit OracleUpdate(_oracle, _trust);
    }

    /**
     * @dev A very simple function wich MUST return false, when `a` is not a maintainer
     *      When derived contracts extend ERC6956 contract, this function may be overridden
     *      e.g. by using AccessControl, onlyOwner or other common mechanisms
     * 
     *      Having this simple mechanism in the reference implementation ensures that the reference
     *      implementation is fully ERC-6956 compatible 
     */
    function isMaintainer(address a) public virtual view returns (bool) {
        return maintainers[a];
    } 
      

    function createAuthorizationMap(ERC6956Authorization _auth) public pure returns (uint8)  {
       uint8 authMap = 0;
       if(_auth == ERC6956Authorization.OWNER 
            || _auth == ERC6956Authorization.OWNER_AND_ASSET 
            || _auth == ERC6956Authorization.OWNER_AND_ISSUER 
            || _auth == ERC6956Authorization.ALL) {
        authMap |= uint8(1<<uint8(ERC6956Role.OWNER));
       } 
       
       if(_auth == ERC6956Authorization.ISSUER 
            || _auth == ERC6956Authorization.ASSET_AND_ISSUER 
            || _auth == ERC6956Authorization.OWNER_AND_ISSUER 
            || _auth == ERC6956Authorization.ALL) {
        authMap |= uint8(1<<uint8(ERC6956Role.ISSUER));
       }

       if(_auth == ERC6956Authorization.ASSET 
            || _auth == ERC6956Authorization.ASSET_AND_ISSUER 
            || _auth == ERC6956Authorization.OWNER_AND_ASSET 
            || _auth == ERC6956Authorization.ALL) {
        authMap |= uint8(1<<uint8(ERC6956Role.ASSET));
       }

       return authMap;
    }

    function _roleBasedAuthorization(bytes32 anchor, uint8 authorizationMap) internal view returns (bool) {
        uint256 tokenId = tokenByAnchor[anchor];        
        ERC6956Role myRole = ERC6956Role.INVALID;
        ERC6956Role alternateRole = ERC6956Role.INVALID;
        
        if(_isApprovedOrOwner(_msgSender(), tokenId)) {
            myRole = ERC6956Role.OWNER;
        }

        if(isMaintainer(msg.sender)) {
            alternateRole = ERC6956Role.ISSUER;
        }

        return hasAuthorization(myRole, authorizationMap) 
                    || hasAuthorization(alternateRole, authorizationMap);
    }
   
    ///@dev Hook executed before decodeAttestationIfValid returns. Override in derived contracts
    function _beforeAttestationUse(bytes32 anchor, address to, bytes memory data) internal view virtual {}
    

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal virtual
        override(ERC721, ERC721Enumerable)
    {
        require(batchSize == 1, "ERC6956-E4");
        bytes32 anchor = anchorByToken[tokenId];
        emit AnchorTransfer(from, to, anchor, tokenId);

        if(to == address(0)) {
            // we are burning, ensure the mapping is deleted BEFORE the transfer
            // to avoid reentrant-attacks
            _burnedTokensByAnchor[anchor] = tokenId; // Remember tokenId for a potential re-mint
            delete tokenByAnchor[anchor];
            delete anchorByToken[tokenId]; 
        }        
        else {
            require(anchorIsReleased[anchor], "ERC6956-E5");
        }
        

    }

    /// @dev hook called after an anchor is minted
    function _afterAnchorMint(address to, bytes32 anchor, uint256 tokenId) internal virtual {}

    /**
     * @notice Add (_add=true) or remove (_add=false) a maintainer
     * @dev Note this is a trivial implementation, which can leave the contract without a maintainer.
     * Since the function is access-controlled via onlyMaintainer, this results in the contract
     * becoming unmaintainable. 
     * This may be desired behavior, for example if the contract shall become immutable until 
     * all eternity, therefore making a project truly trustless. 
     */
    function updateMaintainer(address _maintainer, bool _add) public onlyMaintainer() {
        maintainers[_maintainer] = _add;
    }

    /// @dev Verifies a anchor is valid and mints a token to the target address.
    /// Internal function to be called whenever minting is needed.
    /// Parameters:
    /// @param to Beneficiary account address
    /// @param anchor The anchor (from Merkle tree)
    function _safeMint(address to, bytes32 anchor) internal virtual {
        assert(tokenByAnchor[anchor] <= 0); // saftey for contract-internal errors
        uint256 tokenId = _burnedTokensByAnchor[anchor];

        if(tokenId < 1) {
            _tokenIdCounter.increment();
            tokenId = _tokenIdCounter.current();
        }

        assert(anchorByToken[tokenId] <= 0); // saftey for contract-internal errors
        anchorByToken[tokenId] = anchor;
        tokenByAnchor[anchor] = tokenId;
        super._safeMint(to, tokenId);

        // After minting, the anchor is guaranteed to be dropped.
        // Needs to be explicitely set due to the burn() mechanism, where tokenIds are re-used.
        delete anchorIsReleased[anchor]; 
        _afterAnchorMint(to, anchor, tokenId);
    }

    function _commitAttestation(address to, bytes32 anchor, bytes32 attestationHash) internal {
        _anchorByUsedAttestation[attestationHash] = anchor;
        uint256 totalAttestationsByAnchor = attestationsUsedByAnchor[anchor] +1;
        attestationsUsedByAnchor[anchor] = totalAttestationsByAnchor;
        emit AttestationUse(to, anchor, attestationHash, totalAttestationsByAnchor );
    }

    function transferAnchor(bytes memory attestation, bytes memory data) public virtual
        returns (bytes32 anchor, address to, uint256 tokenId)
    {        
        bytes32 attestationHash;
        (to, anchor, attestationHash) = decodeAttestationIfValid(attestation, data);
        _commitAttestation(to, anchor, attestationHash); // commit already here, will be reverted in error case anyway

        uint256 fromToken = tokenByAnchor[anchor]; // tokenID, null if not exists
        address from = address(0); // owneraddress or 0x00, if not exists

        if(fromToken > 0) {
            from = ownerOf(fromToken);
            require(from != to, "ERC6956-E6");
            bool releaseStateBefore = anchorIsReleased[anchor];
            anchorIsReleased[anchor] = true; // Attestation always temporarily releases the anchor        
            _safeTransfer(from, to, fromToken, "");
            anchorIsReleased[anchor] = releaseStateBefore;
        } else {
            anchorIsReleased[anchor] = true; // Attestation always temporarily releases the anchor
            _safeMint(to, anchor);
        }

        return (anchor, to, tokenId);
    }

    function transferAnchor(bytes memory attestation) public virtual returns (bytes32 anchor, address to, uint256 tokenId){
        return transferAnchor(attestation, "");
    }
    

    function hasAuthorization(ERC6956Role _role, uint8 _auth ) public pure returns (bool) {
        uint8 result = uint8(_auth & (1 << uint8(_role)));
        return result > 0;
    }

    modifier authorized(ERC6956Role _role, uint8 _authMap) {
        require(hasAuthorization(_role, _authMap), "ERC6956-E7");
        _;
    }

    // The following functions are overrides required by Solidity, EIP-165.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return
            interfaceId == type(IERC6956).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @notice Returns whether a certain address is registered as trusted oracle, i.e. attestations signed by this address are accepted in `decodeAttestationIfValid`
     * @dev This function may be overwritten when extending ERC-6956, e.g. when other oracle-registration mechanics are used
     * @param oracleAddress Address of the oracle in question
     * @return isTrusted True, if oracle is trusted
     */
    function isTrustedOracle(address oracleAddress) public virtual view returns (bool isTrusted) {
        return _trustedOracles[oracleAddress];
    }
    

    function decodeAttestationIfValid(bytes memory attestation, bytes memory data) public view returns (address to, bytes32 anchor, bytes32 attestationHash) {
        uint256 attestationTime;
        uint256 validStartTime;
        uint256 validEndTime;
        bytes memory signature;
        bytes32[] memory proof;

        attestationHash = keccak256(attestation);
        (to, anchor, attestationTime, validStartTime, validEndTime, signature) = abi.decode(attestation, (address, bytes32, uint256, uint256, uint256, bytes));
                
        bytes32 messageHash = keccak256(abi.encodePacked(to, anchor, attestationTime, validStartTime, validEndTime, proof));
        address signer = _extractSigner(messageHash, signature);

        // Check if from trusted oracle
        require(isTrustedOracle(signer), "ERC6956-E8");
        require(_anchorByUsedAttestation[attestationHash] <= 0, "ERC6956-E9");

        // Check expiry
        uint256 timestamp = block.timestamp;
        require(timestamp > validStartTime, "ERC6956-E10");
        require(attestationTime + maxAttestationExpireTime > block.timestamp, "ERC6956-E11");
        require(validEndTime > block.timestamp, "ERC6956-E112");

        
        // Calling hook!
        _beforeAttestationUse(anchor, to, data);
        return(to,  anchor, attestationHash);
    }

    function assertAttestation(bytes memory attestation, bytes memory data) 
        public virtual view returns (bool) {
            decodeAttestationIfValid(attestation, data);
            return true;        
    }

    function assertAttestation(bytes memory attestation) public virtual view returns (bool) {
        return assertAttestation(attestation, "");
    }

    /// @notice Compatible with ERC721.tokenURI(). Returns {baseURI}{anchor}
    /// @dev Returns when called for tokenId=5, baseURI=https://myurl.com/collection/ and anchorByToken[5] =  0x12345
    /// Example:  https://myurl.com/collection/0x12345
    /// Works for non-burned tokens / active-Anchors only.
    /// Anchor-based tokenURIs are needed as an anchor's corresponding tokenId is only known after mint. 
    /// @param tokenId TokenID
    /// @return tokenURI Returns the Uniform Resource Identifier (URI) for `tokenId` token.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {        
        bytes32 anchor = anchorByToken[tokenId];
        string memory anchorString = Strings.toHexString(uint256(anchor));
        return bytes(_baseURI()).length > 0 ? string(abi.encodePacked(_baseURI(), anchorString)) : "";
    }

    function _baseURI() internal view virtual override(ERC721) returns (string memory) {
        return _baseUri;
    }

    /**
    * @dev Base URI, MUST end with a slash. Will be used as `{baseURI}{tokenId}` in tokenURI() function
    */
    string internal _baseUri = ""; // needs to end with '/'

    /// @notice Set a new BaseURI. Can be used with dynamic NFTs that have server APIs, IPFS-buckets
    /// or any other suitable system. Refer tokenURI(tokenId) for anchor-based or tokenId-based format.
    /// @param tokenBaseURI The token base-URI. Must end with slash '/'.
    function updateBaseURI(string calldata tokenBaseURI) public onlyMaintainer() {
        _baseUri = tokenBaseURI;
    }
    event BurnAuthorizationChange(ERC6956Authorization burnAuth, address indexed maintainer);

    function updateBurnAuthorization(ERC6956Authorization _burnAuth) public onlyMaintainer() {
        _burnAuthorizationMap = createAuthorizationMap(_burnAuth);
        emit BurnAuthorizationChange(_burnAuth, msg.sender);
        // TODO event
    }
    
    event ApproveAuthorizationChange(ERC6956Authorization approveAuth, address indexed maintainer);

    function updateApproveAuthorization(ERC6956Authorization _approveAuth) public onlyMaintainer() {
        _approveAuthorizationMap = createAuthorizationMap(_approveAuth);
        emit ApproveAuthorizationChange(_approveAuth, msg.sender);

        // TODO event
    }

    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol) {            
            maintainers[msg.sender] = true; // deployer is automatically maintainer
            // Indicates general float-ability, i.e. whether anchors can be digitally dropped and released

            // OWNER and ASSET shall normally be in sync anyway, so this is reasonable default 
            // authorization for approve and burn, as it mimicks ERC-721 behavior
            _burnAuthorizationMap = createAuthorizationMap(ERC6956Authorization.OWNER_AND_ASSET);
            _approveAuthorizationMap = createAuthorizationMap(ERC6956Authorization.OWNER_AND_ASSET);
    }
  
    /*
     ########################## SIGNATURE MAGIC, 
     ########################## adapted from https://solidity-by-example.org/signature/
    */
   /**
    * Returns the signer of a message.
    *  
    *   OFF-CHAIN: 
    *   const [alice] = ethers.getSigners(); // = 0x3c44...
    *   const messageHash = ethers.utils.solidityKeccak256(["address", "bytes32"], [a, b]);
        const sig = await alice.signMessage(ethers.utils.arrayify(messageHash));

        ONCHAIN In this contract, call from 
        ```
        function (address a, bytes32 b, bytes memory sig) {
            messageHash = keccak256(abi.encodePacked(to, b));
            signer = extractSigner(messageHash, sig); // signer will be 0x3c44...
        }
        ```    * 
    * @param messageHash A keccak25(abi.encodePacked(...)) hash
    * @param sig Signature (length 65 bytes)
    * 
    * @return The signer
    */
   function _extractSigner(bytes32 messageHash, bytes memory sig) internal pure returns (address) {
        require(sig.length == 65, "ERC6956-E13");
        /*
        Signature is produced by signing a keccak256 hash with the following format:
        "\x19Ethereum Signed Message\n" + len(msg) + msg
        */
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        bytes32 r;
        bytes32 s;
        uint8 v;

        // Extract the r, s, and v parameters from the signature
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        // Ensure the v parameter is either 27 or 28
        // TODO is this needed?
        if (v < 27) {
            v += 27;
        }

        // Recover the public key from the signature and message hash
        // and convert it to an address
        address signer = ecrecover(ethSignedMessageHash, v, r, s);       
        return signer;
    }
}
