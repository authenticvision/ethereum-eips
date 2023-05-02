import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { createHash } from 'node:crypto';
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import { float } from "hardhat/internal/core/params/argumentTypes";
import { ERC6956Authorization, ERC6956Role, merkleTestAnchors, NULLADDR, createAttestation, AttestedTransferLimitUpdatePolicy, invalidAnchor} from "./commons";

describe("ERC6956: Asset-Bound NFT --- Full", function () {
  // Fixture to deploy the abnftContract contract and assigne roles.
  // Besides owner there's user, minter and burner with appropriate roles.
  async function deployAbNftFixture() {
    // Contracts are deployed using the first signer/account by default
    const [owner, maintainer, oracle, alice, bob, mallory, hacker, carl, gasProvider ] = await ethers.getSigners();

    return actuallyDeploy(10, AttestedTransferLimitUpdatePolicy.FLEXIBLE);
  }

  async function deployAbNftAndMintTokenToAliceFixture() {
    // Contracts are deployed using the first signer/account by default
    const {abnftContract, merkleTree, owner, maintainer, oracle, alice, bob, mallory, hacker, carl, gasProvider} = await deployAbNftFixture();
  
    const anchor = merkleTestAnchors[0][0];
    const mintAttestationAlice = await createAttestation(alice.address, anchor, oracle, merkleTree); // Mint to alice

    const expectedTokenId = 1;
    await expect(abnftContract.connect(gasProvider).transferAnchor(mintAttestationAlice))
    .to.emit(abnftContract, "Transfer") // Standard ERC721 event
    .withArgs(NULLADDR, alice.address, expectedTokenId)
    .to.emit(abnftContract, "AnchorFloatingStateChange") // floating state needs to be announced for each anchor implementing IERC6956Floatable
    .withArgs(anchor, expectedTokenId, false);

    return { abnftContract, merkleTree, owner, maintainer, oracle, mintAttestationAlice, anchor, alice, bob, mallory, hacker, carl, gasProvider };
  }

  async function actuallyDeploy(attestationLimitPerAnchor: number, limitUpdatePolicy: AttestedTransferLimitUpdatePolicy) {
    const [owner, maintainer, oracle, alice, bob, mallory, hacker, carl, gasProvider ] = await ethers.getSigners();

    const AbNftContract = await ethers.getContractFactory("ERC6956Full");

    const abnftContract = await AbNftContract.connect(owner).deploy("Asset-Bound NFT test", "ABNFT", limitUpdatePolicy);
    await abnftContract.connect(owner).grantRole(abnftContract.MAINTAINER_ROLE(), maintainer.address);

    // set attestation Limit per anchor
    await abnftContract.connect(maintainer).updateGlobalAttestationLimit(attestationLimitPerAnchor);

    // Create Merkle Tree
    const merkleTree = StandardMerkleTree.of(merkleTestAnchors, ["bytes32"]);
    await abnftContract.connect(maintainer).updateValidAnchors(merkleTree.root);

    await expect(abnftContract.connect(maintainer).updateOracle(oracle.address, true))
    .to.emit(abnftContract, "OracleUpdate")
    .withArgs(oracle.address, true);

    // Uncomment to see the merkle tree.
    // console.log(merkleTree.dump());

    return { abnftContract, merkleTree, owner, maintainer, oracle, alice, bob, mallory, hacker, carl, gasProvider };
  }

  async function deployForAttestationLimit(limit: number, policy: AttestedTransferLimitUpdatePolicy) {
    return actuallyDeploy(limit, policy);
  }

  /*
  describe("Deployment & Settings", function () {
    it("Should implement EIP-165 support the EIP-6956 interface", async function () {
      const { abnftContract } = await loadFixture(deployPTNFTFixture);
      expect("TODO not implemented yet").to.be.equal(true);
      // FIXME
      // expect(await abnftContract.supportsInterface('0x0489b56f')).to.equal(true);
    });
  });
*/

describe("Anchor-Floating", function () {
  it("SHOULD only allow maintainer to specify canStartFloating and canStopFloating", async function () {
    const { abnftContract, merkleTree, owner, maintainer, mallory } = await loadFixture(deployAbNftAndMintTokenToAliceFixture);

    await expect(abnftContract.canStartFloating(ERC6956Authorization.ALL))
    .to.revertedWith("AccessControl: account 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266 is missing role 0x339759585899103d2ace64958e37e18ccb0504652c81d4a1b8aa80fe2126ab95");

    await expect(abnftContract.connect(maintainer).canStartFloating(ERC6956Authorization.ALL))
    .to.emit(abnftContract, "CanStartFloating")
    .withArgs(ERC6956Authorization.ALL, maintainer.address);
  });

  it("SHOULD only allow maintainer to modify default floating behavior w/o affecting previous tokens", async function () {
    const { abnftContract, merkleTree, anchor, owner, maintainer, bob, oracle, mallory, gasProvider } = await loadFixture(deployAbNftAndMintTokenToAliceFixture);

    const defaultFloatingAnchor = merkleTestAnchors[1][0];
    const mintToBobAttestation = await createAttestation(bob.address, defaultFloatingAnchor, oracle, merkleTree); // Mint to alice
    const expectedTokenId = 2;

    // Mallory mustnot be able to change default behavior
    await expect(abnftContract.connect(mallory).updateAnchorFloatingByDefault(true))
    .to.revertedWith("AccessControl: account 0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc is missing role 0x339759585899103d2ace64958e37e18ccb0504652c81d4a1b8aa80fe2126ab95");

    // Maintainer must be able to update
    await expect(abnftContract.connect(maintainer).updateAnchorFloatingByDefault(true))
    .to.emit(abnftContract, "DefaultFloatingStateChange")
    .withArgs(true, maintainer.address);

    await expect(abnftContract.connect(gasProvider).transferAnchor(mintToBobAttestation))
    .to.emit(abnftContract, "Transfer")
    .withArgs(NULLADDR, bob.address, expectedTokenId)
    .to.emit(abnftContract, "AnchorFloatingStateChange")
    .withArgs(defaultFloatingAnchor, expectedTokenId, true);

    // we expect the original anchor for alice to not be floating, and the new anchor from float to be floating
    expect(await abnftContract.isFloating(anchor))
    .to.be.equal(false); // one was used to mint

    expect(await abnftContract.isFloating(defaultFloatingAnchor))
    .to.be.equal(true); // one was used to mint
  });

  it("SHOULD allow owner to float token only when OWNER is allowed", async function () {
    const { abnftContract, anchor, maintainer, alice, mallory } = await loadFixture(deployAbNftAndMintTokenToAliceFixture);
    const tokenId = await abnftContract.tokenByAnchor(anchor);

    await expect(abnftContract.connect(maintainer).canStartFloating(ERC6956Authorization.ASSET_AND_ISSUER))
    .to.emit(abnftContract, "CanStartFloating")
    .withArgs(ERC6956Authorization.ASSET_AND_ISSUER, maintainer.address);

    await expect(abnftContract.connect(alice).allowFloating(anchor, true))
    .to.revertedWith("ERC-6956: No permission to start floating")

    await expect(abnftContract.connect(maintainer).canStartFloating(ERC6956Authorization.OWNER_AND_ASSET))
    .to.emit(abnftContract, "CanStartFloating")
    .withArgs(ERC6956Authorization.OWNER_AND_ASSET, maintainer.address);

    await expect(abnftContract.connect(alice).allowFloating(anchor, true))
    .to.emit(abnftContract, "AnchorFloatingStateChange")
    .withArgs(anchor, tokenId, true);
  });

  it("SHOULD only allow owner to transfer token when floating", async function () {
    const { abnftContract, anchor, maintainer, alice, bob, mallory } = await loadFixture(deployAbNftAndMintTokenToAliceFixture);
    const tokenId = await abnftContract.tokenByAnchor(anchor);

    await expect(abnftContract.connect(maintainer).canStartFloating(ERC6956Authorization.OWNER_AND_ASSET))
    .to.emit(abnftContract, "CanStartFloating")
    .withArgs(ERC6956Authorization.OWNER_AND_ASSET, maintainer.address);

    await expect(abnftContract.connect(alice).allowFloating(anchor, true))
    .to.emit(abnftContract, "AnchorFloatingStateChange")
    .withArgs(anchor, tokenId, true);

    await expect(abnftContract.connect(mallory).transferFrom(alice.address, mallory.address, tokenId))
    .to.revertedWith("ERC721: caller is not token owner or approved");

    await expect(abnftContract.connect(alice).transferFrom(alice.address, bob.address, tokenId))
    .to.emit(abnftContract, "Transfer")
    .withArgs(alice.address,bob.address, tokenId);
  });


  it("SHOULD allow maintainer to float ANY token only when ISSUER is allowed", async function () {
    const { abnftContract, anchor, maintainer, mallory } = await loadFixture(deployAbNftAndMintTokenToAliceFixture);
    const tokenId = await abnftContract.tokenByAnchor(anchor);

    await expect(abnftContract.connect(maintainer).canStartFloating(ERC6956Authorization.OWNER))
    .to.emit(abnftContract, "CanStartFloating")
    .withArgs(ERC6956Authorization.OWNER, maintainer.address);

    await expect(abnftContract.connect(maintainer).allowFloating(anchor, true))
    .to.revertedWith("ERC-6956: No permission to start floating")

    await expect(abnftContract.connect(maintainer).canStartFloating(ERC6956Authorization.ISSUER))
    .to.emit(abnftContract, "CanStartFloating")
    .withArgs(ERC6956Authorization.ISSUER, maintainer.address);

    await expect(abnftContract.connect(maintainer).allowFloating(anchor, true))
    .to.emit(abnftContract, "AnchorFloatingStateChange")
    .withArgs(anchor, tokenId, true);
  });

  it("SHOULD allow maintainer to float HIS OWN token when ISSUER is allowed", async function () {
    const { abnftContract, anchor, alice, maintainer, oracle, merkleTree, gasProvider } = await loadFixture(deployAbNftAndMintTokenToAliceFixture);
    const tokenId = await abnftContract.tokenByAnchor(anchor);

    // Anchor should not be floating by default...
    expect(await abnftContract.isFloating(anchor))
    .to.be.equal(false); // one was used to mint

    await expect(abnftContract.connect(maintainer).canStartFloating(ERC6956Authorization.OWNER))
    .to.emit(abnftContract, "CanStartFloating")
    .withArgs(ERC6956Authorization.OWNER, maintainer.address);

    await expect(abnftContract.connect(maintainer).allowFloating(anchor, true))
    .to.revertedWith("ERC-6956: No permission to start floating")
    
    const attestationMaintainer = await createAttestation(maintainer.address, anchor, oracle, merkleTree); 
    await expect(abnftContract.connect(gasProvider).transferAnchor(attestationMaintainer))
    .to.emit(abnftContract, "Transfer")
    .withArgs(alice.address, maintainer.address, tokenId)
           
    // Now maintainer owns the token, hence he is owner and can indeed change floating
    await expect(abnftContract.connect(maintainer).allowFloating(anchor, true))
    .to.emit(abnftContract, "AnchorFloatingStateChange")
    .withArgs(anchor, tokenId, true);

    expect(await abnftContract.isFloating(anchor))
    .to.be.equal(true); // one was used to mint
  });

  it("SHOULD allow approveAnchor followed by safeTransfer when anchor IS floating", async function() {
    const { abnftContract, anchor, maintainer, oracle, merkleTree, alice, bob, gasProvider, mallory,carl} = await loadFixture(deployAbNftAndMintTokenToAliceFixture);      
    const tokenId = await abnftContract.tokenByAnchor(anchor);
    const attestationBob = await createAttestation(bob.address, anchor, oracle, merkleTree); // Mint to alice

    // somebody approves himself via attestation approves bob to act on her behalf
    await expect(abnftContract.connect(gasProvider).approveAnchor(attestationBob))
    .to.emit(abnftContract, "Approval") // Standard ERC721 event
    .withArgs(await abnftContract.ownerOf(tokenId), bob.address, tokenId);
    
    // Should not allow mallory to transfer, since only bob is approved
    await expect(abnftContract.connect(mallory).transferFrom(alice.address, bob.address, 1)) 
    .to.revertedWith("ERC721: caller is not token owner or approved");

    await expect(abnftContract.connect(maintainer).canStartFloating(ERC6956Authorization.OWNER))
    .to.emit(abnftContract, "CanStartFloating")
    .withArgs(ERC6956Authorization.OWNER, maintainer.address);

    await expect(abnftContract.connect(alice).allowFloating(anchor, true))
    .to.emit(abnftContract, "AnchorFloatingStateChange")
    .withArgs(anchor, tokenId, true);
    
    await expect(abnftContract.connect(bob).transferFrom(alice.address, carl.address, tokenId))
    .to.emit(abnftContract, "Transfer")
    .withArgs(alice.address,carl.address, tokenId);        
  })

});

describe("Attested Transfer Limits", function () {
  it("SHOULD count attested transfers (transfer, burn, approve)", async function () {
    const { abnftContract, anchor, maintainer, oracle, merkleTree, alice, bob, gasProvider, mallory,carl} = await loadFixture(deployAbNftAndMintTokenToAliceFixture);      
    const tokenId = await abnftContract.tokenByAnchor(anchor);
    const attestationBob = await createAttestation(bob.address, anchor, oracle, merkleTree); // Mint to alice
    const attestationCarl = await createAttestation(carl.address, anchor, oracle, merkleTree); // Mint to alice

    
    // Transfers shall be counted - also the one from the fixture
    expect(await abnftContract.attestationsUsedByAnchor(anchor))
    .to.be.equal(1);

    // Should increase count by 1
    await expect(abnftContract.approveAnchor(attestationBob))
    .to.emit(abnftContract, "Approval") // Standard ERC721 event
    .withArgs(await abnftContract.ownerOf(tokenId), bob.address, tokenId);

    // Should increase count by 1
    await expect(abnftContract.burnAnchor(attestationCarl))
    .to.emit(abnftContract, "Transfer")
    .withArgs(alice.address, NULLADDR, tokenId);

    // InitialMint + Approve + Burns shall also be counted - also the one from the fixture
    expect(await abnftContract.attestationsUsedByAnchor(anchor))
    .to.be.equal(3);

    // Should return 0 for invalid anchors
    expect(await abnftContract.attestationsUsedByAnchor(invalidAnchor))
    .to.be.equal(0);
  });

  it("SHOULD allow maintainer to update global attestation limit", async function () {
    const { abnftContract, maintainer, oracle, merkleTree, alice, bob, gasProvider, mallory,carl} = await deployForAttestationLimit(10, AttestedTransferLimitUpdatePolicy.FLEXIBLE);

    await expect(abnftContract.connect(mallory).updateGlobalAttestationLimit(5))
    .to.revertedWith("AccessControl: account 0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc is missing role 0x339759585899103d2ace64958e37e18ccb0504652c81d4a1b8aa80fe2126ab95");

    // Should be able to update
    await expect(abnftContract.connect(maintainer).updateGlobalAttestationLimit(5))
    .to.emit(abnftContract, "GlobalAttestationLimitUpdate") // Standard ERC721 event
    .withArgs(5, maintainer.address);

    // Check effect, but requesting transfers left from a non-existent anchor
    expect(await abnftContract.attestationUsagesLeft(invalidAnchor))
    .to.be.equal(5);
  });

  it("Should allow maintainer to update anchor-based attestation limit w/o changing global limits", async function () {
    const globalLimit = 10;
    const specificAnchorLimit = 5;
    const { abnftContract, maintainer, oracle, merkleTree, alice, bob, gasProvider, mallory,carl} = await deployForAttestationLimit(globalLimit, AttestedTransferLimitUpdatePolicy.FLEXIBLE);

    const anchor = merkleTestAnchors[0][0];
    const mintAttestationAlice = await createAttestation(alice.address, anchor, oracle, merkleTree); // Mint to alice
    const tokenId = 1;

    await expect(abnftContract.connect(gasProvider).transferAnchor(mintAttestationAlice))
    .to.emit(abnftContract, "Transfer") // Standard ERC721 event
    .withArgs(NULLADDR, alice.address, tokenId);


    // Note that an anchor does not need to exist yet for playing with the limits
    // Check effect, but requesting transfers left from a non-existent anchor
    expect(await abnftContract.attestationUsagesLeft(invalidAnchor))
    .to.be.equal(globalLimit);
    
    // Should be able to update
    await expect(abnftContract.connect(maintainer).updateAttestationLimit(anchor, specificAnchorLimit))
    .to.emit(abnftContract, "AttestationLimitUpdate") // Standard ERC721 event
    .withArgs(anchor, tokenId, specificAnchorLimit, maintainer.address);

    // Check unchanged global effect, but requesting transfers left from a non-existent anchor
    expect(await abnftContract.attestationUsagesLeft(invalidAnchor))
    .to.be.equal(globalLimit);
    
    // Check verify effect
    expect(await abnftContract.attestationUsagesLeft(anchor))
    .to.be.equal(specificAnchorLimit-1); // 1 has been used to mint
  });

  it("Should enforce anchor limits (global + local)", async function () {
    const globalLimit = 2;
    const specificAnchorLimit = 1;
    const { abnftContract, maintainer, oracle, merkleTree, alice, bob, gasProvider, mallory,carl, hacker} = await deployForAttestationLimit(globalLimit, AttestedTransferLimitUpdatePolicy.FLEXIBLE);
    const anchor = merkleTestAnchors[0][0]; // can be transferred twice
    const limitedAnchor = merkleTestAnchors[1][0]; // can be transferred once

    const anchorToAlice = await createAttestation(alice.address, anchor, oracle, merkleTree); // Mint to alice
    const anchorToBob = await createAttestation(bob.address, anchor, oracle, merkleTree); // Transfer to bob
    const anchorToHacker = await createAttestation(hacker.address, anchor, oracle, merkleTree); // Limit reached!

    const limitedAnchorToCarl = await createAttestation(carl.address, limitedAnchor, oracle, merkleTree); // Mint to carl
    const limitedAnchorToMallory = await createAttestation(mallory.address, limitedAnchor, oracle, merkleTree); // Limit reached!
        
    expect(await abnftContract.attestationUsagesLeft(anchor))
    .to.be.equal(globalLimit);

    // ####################################### FIRST ANCHOR
    await expect(abnftContract.connect(gasProvider).transferAnchor(anchorToAlice))
    .to.emit(abnftContract, "Transfer");

    await expect(abnftContract.connect(gasProvider).transferAnchor(anchorToBob))
    .to.emit(abnftContract, "Transfer");

    await expect(abnftContract.connect(gasProvider).transferAnchor(anchorToHacker))
    .to.revertedWith("ERC-6956: No attested transfers left");

    // ###################################### SECOND ANCHOR
    await expect(abnftContract.connect(gasProvider).transferAnchor(limitedAnchorToCarl))
    .to.emit(abnftContract, "Transfer");

    // Update anchor based limit
    await expect(abnftContract.connect(maintainer).updateAttestationLimit(limitedAnchor, specificAnchorLimit))
    .to.emit(abnftContract, "AttestationLimitUpdate") 
    .withArgs(limitedAnchor, 2, specificAnchorLimit, maintainer.address);
    
    expect(await abnftContract.attestationUsagesLeft(limitedAnchor))
    .to.be.equal(specificAnchorLimit-1); // one was used to mint

    await expect(abnftContract.connect(gasProvider).transferAnchor(limitedAnchorToMallory))
    .to.revertedWith("ERC-6956: No attested transfers left");
  });
});
  
});
