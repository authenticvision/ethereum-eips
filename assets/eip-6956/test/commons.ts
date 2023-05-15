import { ethers } from "hardhat";
import { createHash } from 'node:crypto';
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import { float } from "hardhat/internal/core/params/argumentTypes";


export enum ERC6956Authorization {
    NONE,// = 0, // None of the above - a 1:1 relationship is maintained
    OWNER,// = (1 << 1), // The owner of the token, i.e. the digital representation
    ISSUER,// = (1 << 2), // The issuer of the tokens, i.e. this smart contract
    ASSET,// = (1<< 3), // The asset, i.e. via attestation
    OWNER_AND_ISSUER,// = (1<<1) | (1<<2),
    OWNER_AND_ASSET,// = (1<<1) | (1<<3),
    ASSET_AND_ISSUER,// = (1<<3) | (1<<2),
    ALL// = (1<<1) | (1<<2) | (1<<3) // Owner + Issuer + Asset
    }
    
export enum ERC6956Role {
    OWNER,
    ISSUER,
    ASSET
    }

export enum AttestedTransferLimitUpdatePolicy {
        IMMUTABLE,
        INCREASE_ONLY,
        DECREASE_ONLY,
        FLEXIBLE
    }
    
export const invalidAnchor = '0x' + createHash('sha256').update('TestAnchor1239').digest('hex');
export const NULLADDR = ethers.utils.getAddress('0x0000000000000000000000000000000000000000');
    
    // Needs to be an odd number of anchors to test the edge case of the merkle-
    // tree: Nodes with only one leaf.
    // Also: When building the tree (see buildMerkleTree fixture) those hashes are
    // hashed again. This is intended because of the way Merkle-Proof and our
    // smart contract works:
    // Proof = H(leave) + H(L1) + H(L0)
    // Our contract uses hashed anchor numbers as identifiers.
    // Hence if we use direct anchor number checksums, H(leave) would 
    // be an actually valid anchor number on the smart contract.
    export const merkleTestAnchors = [
    ['0x' + createHash('sha256').update('TestAnchor123').digest('hex')],
    ['0x' + createHash('sha256').update('TestAnchor124').digest('hex')],
    ['0x' + createHash('sha256').update('TestAnchor125').digest('hex')],
    ['0x' + createHash('sha256').update('TestAnchor126').digest('hex')],
    ['0x' + createHash('sha256').update('TestAnchor127').digest('hex')]
    ]


export async function createAttestation(to, anchor, signer, validStartTime= 0) {


        const attestationTime = Math.floor(Date.now() / 1000.0); // Now in seconds
        const expiryTime = attestationTime + 5 * 60; // 5min valid
        //const proof = merkleTree.getProof([anchor]);

        const messageHash = ethers.utils.solidityKeccak256(["address", "bytes32", "uint256", 'uint256', "uint256"], [to, anchor, attestationTime, validStartTime, expiryTime]);
        const sig = await signer.signMessage(ethers.utils.arrayify(messageHash));
       
       
        return ethers.utils.defaultAbiCoder.encode(['address', 'bytes32', 'uint256', 'uint256', 'uint256', 'bytes'], [to, anchor, attestationTime,  validStartTime, expiryTime, sig]);
      }


export async function createAttestationWithData(to, anchor, signer, merkleTree, validStartTime= 0) {

        const attestation = await createAttestation(to, anchor, signer, validStartTime); // Now in seconds
        
        const proof = merkleTree.getProof([anchor]);
        const data = ethers.utils.defaultAbiCoder.encode(['bytes32[]'], [proof])
              
        return  [attestation, data];
}




// ##################### Interface-IDs
/*import { IERC6956__factory } from "../typechain-types/factories/contracts/IERC6956__factory";
import { IERC6956Floatable__factory } from "../typechain-types/factories/contracts/IERC6956Floatable__factory";
import { IERC6956AttestationLimited__factory } from "../typechain-types/factories/contracts/IERC6956AttestationLimited__factory";
import {  IERC6956ValidAnchors__factory } from "../typechain-types/factories/contracts/IERC6956ValidAnchors__factory";


function getInterfaceID(contractInterface: ethers.utils.Interface) {
    let interfaceID: ethers.BigNumber = ethers.constants.Zero;
    const functions: string[] = Object.keys(contractInterface.functions);
    for (let i=0; i< functions.length; i++) {
        interfaceID = interfaceID.xor(contractInterface.getSighash(functions[i]));
    }

    const initialHexStr = interfaceID.toHexString();
    // zero-pad it...
    return initialHexStr.replace('0x', '0x' + "0".repeat(10-initialHexStr.length))   
  }



const IERC6956Interface = IERC6956__factory.createInterface();
export const IERC6956InterfaceId = getInterfaceID(IERC6956Interface);

const IERC6956AttestationLimitedInterface = IERC6956AttestationLimited__factory.createInterface();
export const IERC6956AttestationLimitedInterfaceId = getInterfaceID(IERC6956AttestationLimitedInterface);

const IERC6959FloatableInterface = IERC6956Floatable__factory.createInterface();
export const IERC6956FloatableInterfaceId = getInterfaceID(IERC6959FloatableInterface);

const IERC6959ValidAnchors = IERC6956ValidAnchors__factory.createInterface();
export const IERC6956ValidAnchorsInterfaceId = getInterfaceID(IERC6959ValidAnchors);
*/

export const IERC6956InterfaceId = '0xe3e216f4';
export const IERC6956AttestationLimitedInterfaceId ='0xe3787865'
export const IERC6956FloatableInterfaceId = '0xb050a772';
export const IERC6956ValidAnchorsInterfaceId = '0x28a8f107';
