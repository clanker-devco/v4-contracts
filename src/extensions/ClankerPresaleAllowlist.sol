// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerPresaleAllowlist} from "./interfaces/IClankerPresaleAllowlist.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract ClankerPresaleAllowlist is IClankerPresaleAllowlist {
    error InvalidProof();
    error MerkleRootNotSet();

    event Initialize(uint256 indexed presaleId, address indexed presaleOwner, bytes32 merkleRoot);
    event SetAddressOverride(
        uint256 indexed presaleId, address indexed buyer, uint256 allowedAmount
    );
    event SetMerkleRoot(uint256 indexed presaleId, bytes32 merkleRoot);
    event SetAllowlistEnabled(uint256 indexed presaleId, bool enabled);

    struct AllowlistInitializationData {
        bytes32 merkleRoot;
    }

    struct AllowlistProof {
        uint256 allowedAmount;
        bytes32[] proof;
    }

    struct PresaleAllowlist {
        address presaleOwner;
        bytes32 merkleRoot;
        bool enabled;
        mapping(address user => uint256 maxAmount) addressOverrides;
    }

    address public immutable presale;
    mapping(uint256 presaleId => PresaleAllowlist allowlist) public allowlists;

    constructor(address presale_) {
        presale = presale_;
    }

    function setAddressOverride(uint256 presaleId, address buyer, uint256 allowedAmount) external {
        if (allowlists[presaleId].presaleOwner != msg.sender) revert Unauthorized();
        allowlists[presaleId].addressOverrides[buyer] = allowedAmount;
        emit SetAddressOverride(presaleId, buyer, allowedAmount);
    }

    function setMerkleRoot(uint256 presaleId, bytes32 merkleRoot) external {
        if (allowlists[presaleId].presaleOwner != msg.sender) revert Unauthorized();
        allowlists[presaleId].merkleRoot = merkleRoot;
        emit SetMerkleRoot(presaleId, merkleRoot);
    }

    function setAllowlistEnabled(uint256 presaleId, bool enabled) external {
        if (allowlists[presaleId].presaleOwner != msg.sender) revert Unauthorized();
        allowlists[presaleId].enabled = enabled;
        emit SetAllowlistEnabled(presaleId, enabled);
    }

    // called once per presale to pass in allowlist specific data
    function initialize(uint256 presaleId, address presaleOwner, bytes memory initializationData)
        external
    {
        // only presale can call this function
        if (msg.sender != presale) revert Unauthorized();

        allowlists[presaleId].presaleOwner = presaleOwner;

        // only set the merkle root if it is provided
        if (initializationData.length == 0) {
            allowlists[presaleId].merkleRoot = bytes32(0);
        } else {
            AllowlistInitializationData memory allowlistData =
                abi.decode(initializationData, (AllowlistInitializationData));
            allowlists[presaleId].merkleRoot = allowlistData.merkleRoot;
        }

        // start the allowlist as enabled
        allowlists[presaleId].enabled = true;

        emit Initialize(presaleId, presaleOwner, allowlists[presaleId].merkleRoot);
    }

    // check if a user is allowed to participate in a presale for a total amount
    function getAllowedAmountForBuyer(uint256 presaleId, address buyer, bytes calldata proof)
        external
        view
        returns (uint256)
    {
        // check if the allowlist is enabled, if it's not then all buyers are allowed
        // to purchase as much as they would like
        if (!allowlists[presaleId].enabled) {
            return type(uint256).max;
        }

        // check if the buyer is allowlisted in the override
        if (allowlists[presaleId].addressOverrides[buyer] > 0) {
            return allowlists[presaleId].addressOverrides[buyer];
        }

        // if the proof is empty, return 0
        if (proof.length == 0) {
            return 0;
        }

        if (allowlists[presaleId].merkleRoot == bytes32(0)) {
            revert MerkleRootNotSet();
        }

        // use proof to generate user's allowed amount
        AllowlistProof memory allowlistProof = abi.decode(proof, (AllowlistProof));

        if (allowlistProof.allowedAmount == 0) {
            return 0;
        }

        // verify proof
        if (
            !MerkleProof.verify(
                allowlistProof.proof,
                allowlists[presaleId].merkleRoot,
                keccak256(bytes.concat(keccak256(abi.encode(buyer, allowlistProof.allowedAmount))))
            )
        ) {
            revert InvalidProof();
        }

        return allowlistProof.allowedAmount;
    }
}