// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BiometricVerifier
 * @dev Verifies biometric-based digital signatures and blind signatures from hardware voting terminals
 * Implements cryptographic verification for the distributed ledger-based electronic voting system
 */
contract BiometricVerifier is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes;

    struct BiometricTemplate {
        bytes32 templateHash;
        address publicKey;
        uint256 enrollmentTime;
        bool isActive;
        uint256 lastUsed;
    }

    struct BlindSignatureData {
        bytes32 blindedMessage;
        bytes signature;
        bytes32 blindingFactor;
        address signer;
        uint256 timestamp;
    }

    struct ZKProof {
        bytes32 commitment;
        bytes32 challenge;
        bytes32 response;
        bytes32[] publicParams;
    }

    // Mapping from voter ID to biometric template
    mapping(bytes32 => BiometricTemplate) public biometricTemplates;
    
    // Mapping from nullifier to prevent double voting
    mapping(bytes32 => bool) public usedNullifiers;
    
    // Mapping to track anonymous tokens
    mapping(bytes32 => bool) public validTokens;
    
    // Trusted hardware public keys
    mapping(address => bool) public trustedHardware;
    
    // Events
    event BiometricEnrolled(bytes32 indexed voterId, address indexed publicKey);
    event BiometricVerified(bytes32 indexed voterId, uint256 timestamp);
    event BlindSignatureVerified(bytes32 indexed messageHash, address indexed signer);
    event NullifierUsed(bytes32 indexed nullifier);
    event HardwareTrusted(address indexed hardwareKey, bool trusted);
    event ZKProofVerified(bytes32 indexed commitment, bool valid);

    // Custom errors
    error BiometricNotEnrolled();
    error BiometricInactive();
    error InvalidSignature();
    error NullifierAlreadyUsed();
    error UntrustedHardware();
    error InvalidZKProof();
    error TemplateExpired();

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Enroll a new biometric template
     * @param voterId Unique voter identifier derived from biometric hash
     * @param templateHash Hash of the biometric template
     * @param publicKey Public key associated with the biometric
     */
    function enrollBiometric(
        bytes32 voterId,
        bytes32 templateHash,
        address publicKey
    ) external onlyOwner {
        require(voterId != bytes32(0), "Invalid voter ID");
        require(templateHash != bytes32(0), "Invalid template hash");
        require(publicKey != address(0), "Invalid public key");

        biometricTemplates[voterId] = BiometricTemplate({
            templateHash: templateHash,
            publicKey: publicKey,
            enrollmentTime: block.timestamp,
            isActive: true,
            lastUsed: 0
        });

        emit BiometricEnrolled(voterId, publicKey);
    }

    /**
     * @dev Verify biometric-based signature
     * @param voterId Voter identifier
     * @param message Original message that was signed
     * @param signature Signature from hardware device
     * @return bool indicating verification success
     */
    function verifyBiometricSignature(
        bytes32 voterId,
        bytes memory message,
        bytes memory signature
    ) external nonReentrant returns (bool) {
        BiometricTemplate storage template = biometricTemplates[voterId];
        
        if (template.templateHash == bytes32(0)) {
            revert BiometricNotEnrolled();
        }
        
        if (!template.isActive) {
            revert BiometricInactive();
        }

        // Check if template is not expired (optional: implement expiry logic)
        // if (block.timestamp > template.enrollmentTime + TEMPLATE_EXPIRY) {
        //     revert TemplateExpired();
        // }

        bytes32 messageHash = message.toEthSignedMessageHash();
        address recoveredSigner = messageHash.recover(signature);

        if (recoveredSigner != template.publicKey) {
            revert InvalidSignature();
        }

        // Update last used timestamp
        template.lastUsed = block.timestamp;

        emit BiometricVerified(voterId, block.timestamp);
        return true;
    }

    /**
     * @dev Verify blind signature for anonymous voting
     * @param blindedMessage The blinded message hash
     * @param signature Signature on the blinded message
     * @param blindingFactor Factor used for blinding
     * @param originalMessage Original message before blinding
     * @return bool indicating verification success
     */
    function verifyBlindSignature(
        bytes32 blindedMessage,
        bytes memory signature,
        bytes32 blindingFactor,
        bytes memory originalMessage
    ) external view returns (bool) {
        // Recover signer from signature
        bytes32 signedHash = blindedMessage.toEthSignedMessageHash();
        address signer = signedHash.recover(signature);

        // Verify signer is trusted hardware
        if (!trustedHardware[signer]) {
            revert UntrustedHardware();
        }

        // Verify blind signature integrity
        // In a real implementation, this would involve proper unblinding verification
        bytes32 originalHash = keccak256(originalMessage);
        bytes32 reconstructedBlindedHash = keccak256(abi.encodePacked(originalHash, blindingFactor));

        return reconstructedBlindedHash == blindedMessage;
    }

    /**
     * @dev Verify zero-knowledge proof for anonymous voting eligibility
     * @param proof Zero-knowledge proof structure
     * @param publicInput Public input for proof verification
     * @return bool indicating proof validity
     */
    function verifyZKProof(
        ZKProof memory proof,
        bytes32 publicInput
    ) external pure returns (bool) {
        // Simplified ZK proof verification
        // In production, integrate with a proper ZK library (e.g., Circom/snarkjs)
        
        // Verify proof structure
        if (proof.commitment == bytes32(0) || 
            proof.challenge == bytes32(0) || 
            proof.response == bytes32(0)) {
            return false;
        }

        // Simplified verification: check that response corresponds to commitment and challenge
        bytes32 expectedResponse = keccak256(abi.encodePacked(
            proof.commitment,
            proof.challenge,
            publicInput
        ));

        emit ZKProofVerified(proof.commitment, expectedResponse == proof.response);
        return expectedResponse == proof.response;
    }

    /**
     * @dev Mark nullifier as used to prevent double voting
     * @param nullifier Unique nullifier derived from biometric and vote ID
     */
    function markNullifierUsed(bytes32 nullifier) external {
        require(msg.sender == owner() || trustedHardware[msg.sender], "Unauthorized");
        
        if (usedNullifiers[nullifier]) {
            revert NullifierAlreadyUsed();
        }

        usedNullifiers[nullifier] = true;
        emit NullifierUsed(nullifier);
    }

    /**
     * @dev Check if nullifier has been used
     * @param nullifier Nullifier to check
     * @return bool indicating if nullifier was used
     */
    function isNullifierUsed(bytes32 nullifier) external view returns (bool) {
        return usedNullifiers[nullifier];
    }

    /**
     * @dev Add or remove trusted hardware device
     * @param hardwareKey Public key of hardware device
     * @param trusted Whether to trust this hardware
     */
    function setTrustedHardware(address hardwareKey, bool trusted) external onlyOwner {
        trustedHardware[hardwareKey] = trusted;
        emit HardwareTrusted(hardwareKey, trusted);
    }

    /**
     * @dev Generate nullifier from biometric hash and vote ID
     * @param biometricHash Hash derived from biometric data
     * @param voteId Unique vote identifier
     * @return bytes32 nullifier
     */
    function generateNullifier(
        bytes32 biometricHash,
        bytes32 voteId
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(biometricHash, voteId));
    }

    /**
     * @dev Validate anonymous token
     * @param tokenId Token identifier
     * @param commitment Zero-knowledge commitment
     * @param signature Token signature
     * @return bool indicating token validity
     */
    function validateAnonymousToken(
        bytes32 tokenId,
        bytes32 commitment,
        bytes memory signature
    ) external view returns (bool) {
        // Verify token hasn't been revoked
        if (!validTokens[tokenId]) {
            return false;
        }

        // Verify token signature
        bytes32 tokenHash = keccak256(abi.encodePacked(tokenId, commitment));
        address signer = tokenHash.toEthSignedMessageHash().recover(signature);

        return trustedHardware[signer];
    }

    /**
     * @dev Issue anonymous token (only trusted hardware)
     * @param tokenId Unique token identifier
     */
    function issueAnonymousToken(bytes32 tokenId) external {
        require(trustedHardware[msg.sender], "Only trusted hardware can issue tokens");
        validTokens[tokenId] = true;
    }

    /**
     * @dev Revoke anonymous token
     * @param tokenId Token to revoke
     */
    function revokeAnonymousToken(bytes32 tokenId) external onlyOwner {
        validTokens[tokenId] = false;
    }

    /**
     * @dev Get biometric template info
     * @param voterId Voter identifier
     * @return template BiometricTemplate struct
     */
    function getBiometricTemplate(bytes32 voterId) 
        external 
        view 
        returns (BiometricTemplate memory) 
    {
        return biometricTemplates[voterId];
    }

    /**
     * @dev Deactivate biometric template
     * @param voterId Voter identifier
     */
    function deactivateBiometric(bytes32 voterId) external onlyOwner {
        biometricTemplates[voterId].isActive = false;
    }

    /**
     * @dev Batch verify multiple signatures (gas optimization)
     * @param voterIds Array of voter identifiers
     * @param messages Array of messages
     * @param signatures Array of signatures
     * @return results Array of verification results
     */
    function batchVerifySignatures(
        bytes32[] memory voterIds,
        bytes[] memory messages,
        bytes[] memory signatures
    ) external view returns (bool[] memory results) {
        require(
            voterIds.length == messages.length && 
            messages.length == signatures.length,
            "Array length mismatch"
        );

        results = new bool[](voterIds.length);

        for (uint256 i = 0; i < voterIds.length; i++) {
            BiometricTemplate memory template = biometricTemplates[voterIds[i]];
            
            if (template.templateHash == bytes32(0) || !template.isActive) {
                results[i] = false;
                continue;
            }

            bytes32 messageHash = messages[i].toEthSignedMessageHash();
            address recoveredSigner = messageHash.recover(signatures[i]);
            results[i] = (recoveredSigner == template.publicKey);
        }
    }
}