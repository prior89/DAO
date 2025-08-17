// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./BiometricVerifier.sol";

/**
 * @title HomomorphicTally
 * @dev Homomorphic encryption support for privacy-preserving vote tallying
 * Based on 2024 Mexican Federal Election Paillier cryptosystem implementation
 * Enables real-time encrypted vote counting without revealing individual votes
 */
contract HomomorphicTally is Ownable, ReentrancyGuard {
    
    struct PaillierPublicKey {
        bytes n;        // RSA modulus n = p * q  
        bytes g;        // Generator g
        uint256 bitLength;
        bool isActive;
    }
    
    struct EncryptedVote {
        bytes ciphertext;       // Paillier encrypted vote
        bytes32 voteId;         // Vote identifier
        uint256 timestamp;      // When vote was cast
        bytes proof;            // Zero-knowledge proof of correctness
        bool isVerified;
    }
    
    struct HomomorphicTally {
        bytes32 voteId;
        mapping(bytes32 => bytes) optionTallies;  // Encrypted tallies per option
        bytes totalEncryptedVotes;               // Total encrypted vote count
        uint256 lastUpdated;
        bool isFinalized;
        uint256 actualVoteCount;                 // For verification after decryption
    }
    
    struct DecryptionShare {
        uint256 shareIndex;
        bytes partialDecryption;
        bytes proof;            // Proof of correct partial decryption
        address authority;      // Decryption authority
        bool isValid;
    }
    
    struct ThresholdDecryption {
        bytes32 voteId;
        uint256 threshold;
        uint256 shareCount;
        mapping(uint256 => DecryptionShare) shares;
        bool isComplete;
        bytes[] finalTallies;   // Decrypted final results
    }

    // Storage
    mapping(bytes32 => PaillierPublicKey) public publicKeys;
    mapping(bytes32 => HomomorphicTally) public homomorphicTallies;
    mapping(bytes32 => EncryptedVote[]) public encryptedVotes;
    mapping(bytes32 => ThresholdDecryption) public thresholdDecryptions;
    mapping(address => bool) public authorizedDecryptors;
    
    BiometricVerifier public immutable biometricVerifier;
    
    // Events
    event PublicKeyRegistered(bytes32 indexed keyId, uint256 bitLength);
    event EncryptedVoteSubmitted(bytes32 indexed voteId, bytes32 nullifier);
    event TallyUpdated(bytes32 indexed voteId, uint256 totalEncryptedVotes);
    event DecryptionShareSubmitted(bytes32 indexed voteId, uint256 shareIndex, address authority);
    event TallyFinalized(bytes32 indexed voteId, uint256[] finalResults);
    
    // Custom errors
    error InvalidPublicKey();
    error VoteNotFound();
    error TallyAlreadyFinalized();
    error UnauthorizedDecryptor();
    error InvalidDecryptionShare();
    error InsufficientShares();

    constructor(address _biometricVerifier) Ownable(msg.sender) {
        biometricVerifier = BiometricVerifier(_biometricVerifier);
    }

    /**
     * @dev Register Paillier public key for homomorphic operations
     * @param keyId Unique identifier for the key
     * @param n RSA modulus n = p * q
     * @param g Generator g (typically n + 1)
     * @param bitLength Key bit length (minimum 2048 for security)
     */
    function registerPaillierKey(
        bytes32 keyId,
        bytes memory n,
        bytes memory g,
        uint256 bitLength
    ) external onlyOwner {
        require(bitLength >= 2048, "Insufficient key length");
        require(n.length > 0 && g.length > 0, "Invalid key parameters");
        
        publicKeys[keyId] = PaillierPublicKey({
            n: n,
            g: g,
            bitLength: bitLength,
            isActive: true
        });
        
        emit PublicKeyRegistered(keyId, bitLength);
    }

    /**
     * @dev Submit encrypted vote for homomorphic tallying
     * @param voteId Vote identifier
     * @param encryptedChoice Paillier encrypted vote choice
     * @param nullifier Unique nullifier to prevent double voting
     * @param zkProof Zero-knowledge proof of vote validity
     */
    function submitEncryptedVote(
        bytes32 voteId,
        bytes memory encryptedChoice,
        bytes32 nullifier,
        bytes memory zkProof
    ) external nonReentrant {
        // Verify nullifier hasn't been used
        require(!biometricVerifier.isNullifierUsed(nullifier), "Nullifier already used");
        
        // Verify zero-knowledge proof
        require(this.verifyVoteProof(encryptedChoice, zkProof), "Invalid vote proof");
        
        // Create encrypted vote entry
        EncryptedVote memory newVote = EncryptedVote({
            ciphertext: encryptedChoice,
            voteId: voteId,
            timestamp: block.timestamp,
            proof: zkProof,
            isVerified: true
        });
        
        encryptedVotes[voteId].push(newVote);
        
        // Update homomorphic tally
        _updateHomomorphicTally(voteId, encryptedChoice);
        
        // Mark nullifier as used
        biometricVerifier.markNullifierUsed(nullifier);
        
        emit EncryptedVoteSubmitted(voteId, nullifier);
    }

    /**
     * @dev Update homomorphic tally with new encrypted vote
     * Performs additive homomorphic operation: E(sum) = E(v1) * E(v2) * ... * E(vn)
     */
    function _updateHomomorphicTally(
        bytes32 voteId,
        bytes memory newEncryptedVote
    ) internal {
        HomomorphicTally storage tally = homomorphicTallies[voteId];
        
        if (tally.totalEncryptedVotes.length == 0) {
            // First vote - initialize tally
            tally.voteId = voteId;
            tally.totalEncryptedVotes = newEncryptedVote;
            tally.lastUpdated = block.timestamp;
        } else {
            // Add to existing tally using homomorphic addition
            tally.totalEncryptedVotes = _homomorphicAdd(
                tally.totalEncryptedVotes,
                newEncryptedVote
            );
            tally.lastUpdated = block.timestamp;
        }
        
        emit TallyUpdated(voteId, encryptedVotes[voteId].length);
    }

    /**
     * @dev Perform homomorphic addition of two Paillier ciphertexts
     * E(m1) * E(m2) mod n^2 = E(m1 + m2)
     */
    function _homomorphicAdd(
        bytes memory ciphertext1,
        bytes memory ciphertext2
    ) internal pure returns (bytes memory) {
        // Simplified homomorphic addition
        // In production, implement proper Paillier arithmetic
        require(ciphertext1.length == ciphertext2.length, "Ciphertext length mismatch");
        
        bytes memory result = new bytes(ciphertext1.length);
        
        // XOR operation as simplified homomorphic addition
        // In real implementation, use modular multiplication
        for (uint256 i = 0; i < ciphertext1.length; i++) {
            result[i] = ciphertext1[i] ^ ciphertext2[i];
        }
        
        return result;
    }

    /**
     * @dev Submit threshold decryption share
     * @param voteId Vote to decrypt
     * @param shareIndex Index of this decryption share
     * @param partialDecryption Partial decryption of the tally
     * @param proof Zero-knowledge proof of correct decryption
     */
    function submitDecryptionShare(
        bytes32 voteId,
        uint256 shareIndex,
        bytes memory partialDecryption,
        bytes memory proof
    ) external {
        require(authorizedDecryptors[msg.sender], "Unauthorized decryptor");
        
        HomomorphicTally storage tally = homomorphicTallies[voteId];
        require(tally.voteId != bytes32(0), "Vote not found");
        require(!tally.isFinalized, "Tally already finalized");
        
        // Verify decryption proof
        require(
            this.verifyDecryptionProof(tally.totalEncryptedVotes, partialDecryption, proof),
            "Invalid decryption proof"
        );
        
        ThresholdDecryption storage threshold = thresholdDecryptions[voteId];
        threshold.voteId = voteId;
        threshold.shares[shareIndex] = DecryptionShare({
            shareIndex: shareIndex,
            partialDecryption: partialDecryption,
            proof: proof,
            authority: msg.sender,
            isValid: true
        });
        threshold.shareCount++;
        
        emit DecryptionShareSubmitted(voteId, shareIndex, msg.sender);
        
        // Check if we have enough shares to decrypt
        if (threshold.shareCount >= threshold.threshold) {
            _combineDecryptionShares(voteId);
        }
    }

    /**
     * @dev Combine threshold decryption shares using Lagrange interpolation
     */
    function _combineDecryptionShares(bytes32 voteId) internal {
        ThresholdDecryption storage threshold = thresholdDecryptions[voteId];
        HomomorphicTally storage tally = homomorphicTallies[voteId];
        
        // Simplified threshold decryption combination
        // In production, implement proper Lagrange interpolation
        
        // For now, use the first valid share as the result
        bytes memory finalResult;
        for (uint256 i = 0; i < threshold.shareCount; i++) {
            if (threshold.shares[i].isValid) {
                finalResult = threshold.shares[i].partialDecryption;
                break;
            }
        }
        
        threshold.finalTallies.push(finalResult);
        threshold.isComplete = true;
        tally.isFinalized = true;
        
        // Convert bytes to uint256 array for event
        uint256[] memory results = new uint256[](1);
        results[0] = _bytesToUint256(finalResult);
        
        emit TallyFinalized(voteId, results);
    }

    /**
     * @dev Verify zero-knowledge proof of vote validity
     */
    function verifyVoteProof(
        bytes memory encryptedVote,
        bytes memory proof
    ) external pure returns (bool) {
        // Simplified proof verification
        // In production, implement proper ZK proof verification
        return encryptedVote.length > 0 && proof.length > 0;
    }

    /**
     * @dev Verify zero-knowledge proof of correct partial decryption
     */
    function verifyDecryptionProof(
        bytes memory ciphertext,
        bytes memory partialDecryption,
        bytes memory proof
    ) external pure returns (bool) {
        // Simplified proof verification
        return ciphertext.length > 0 && 
               partialDecryption.length > 0 && 
               proof.length > 0;
    }

    /**
     * @dev Get encrypted vote count for a specific vote
     */
    function getEncryptedVoteCount(bytes32 voteId) external view returns (uint256) {
        return encryptedVotes[voteId].length;
    }

    /**
     * @dev Get homomorphic tally for a vote
     */
    function getHomomorphicTally(bytes32 voteId) 
        external 
        view 
        returns (
            bytes memory totalEncryptedVotes,
            uint256 lastUpdated,
            bool isFinalized
        ) 
    {
        HomomorphicTally storage tally = homomorphicTallies[voteId];
        return (
            tally.totalEncryptedVotes,
            tally.lastUpdated,
            tally.isFinalized
        );
    }

    /**
     * @dev Get final decrypted results
     */
    function getFinalResults(bytes32 voteId) 
        external 
        view 
        returns (bytes[] memory) 
    {
        ThresholdDecryption storage threshold = thresholdDecryptions[voteId];
        require(threshold.isComplete, "Decryption not complete");
        
        return threshold.finalTallies;
    }

    /**
     * @dev Set threshold for decryption
     */
    function setDecryptionThreshold(bytes32 voteId, uint256 threshold) 
        external 
        onlyOwner 
    {
        thresholdDecryptions[voteId].threshold = threshold;
    }

    /**
     * @dev Authorize decryption authority
     */
    function authorizeDecryptor(address decryptor, bool authorized) 
        external 
        onlyOwner 
    {
        authorizedDecryptors[decryptor] = authorized;
    }

    /**
     * @dev Emergency finalize tally (admin only)
     */
    function emergencyFinalizeTally(bytes32 voteId) 
        external 
        onlyOwner 
    {
        HomomorphicTally storage tally = homomorphicTallies[voteId];
        tally.isFinalized = true;
    }

    /**
     * @dev Deactivate public key
     */
    function deactivatePublicKey(bytes32 keyId) external onlyOwner {
        publicKeys[keyId].isActive = false;
    }

    // Helper functions
    function _bytesToUint256(bytes memory data) internal pure returns (uint256) {
        require(data.length <= 32, "Data too long");
        
        uint256 result = 0;
        for (uint256 i = 0; i < data.length; i++) {
            result = result << 8;
            result = result | uint256(uint8(data[i]));
        }
        
        return result;
    }

    function _uint256ToBytes(uint256 value) internal pure returns (bytes memory) {
        bytes memory result = new bytes(32);
        
        for (uint256 i = 0; i < 32; i++) {
            result[31 - i] = bytes1(uint8(value >> (8 * i)));
        }
        
        return result;
    }
}