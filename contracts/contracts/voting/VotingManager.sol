// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../crypto/BiometricVerifier.sol";
import "../crypto/HomomorphicTally.sol";

/**
 * @title VotingManager
 * @dev Manages biometric-authenticated voting sessions with privacy protection
 * Supports DeFi governance, NFT community decisions, and corporate governance
 */
contract VotingManager is AccessControl, ReentrancyGuard, Pausable {
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VOTE_CREATOR_ROLE = keccak256("VOTE_CREATOR_ROLE");
    bytes32 public constant HARDWARE_ROLE = keccak256("HARDWARE_ROLE");

    enum VoteType {
        DEFI_GOVERNANCE,     // DeFi protocol policy changes
        NFT_COMMUNITY,       // NFT community operation decisions
        CORPORATE_GOVERNANCE // Corporate decision making
    }

    enum VoteStatus {
        CREATED,
        ACTIVE,
        ENDED,
        FINALIZED
    }

    struct Vote {
        bytes32 id;
        string title;
        string description;
        VoteType voteType;
        VoteStatus status;
        uint256 startTime;
        uint256 endTime;
        address creator;
        bytes32[] options;
        mapping(bytes32 => uint256) optionVotes; // option hash => vote count
        mapping(bytes32 => bool) hasVoted; // nullifier => bool
        uint256 totalVotes;
        bool requiresBiometric;
        bool allowsBlindVoting;
        bytes32 templateHash; // For vote-specific templates
    }

    struct VoteOption {
        bytes32 id;
        string title;
        string description;
    }

    struct EncryptedVote {
        bytes32 voteId;
        bytes encryptedChoice;
        bytes signature;
        bytes32 nullifier;
        uint256 timestamp;
    }

    struct HomomorphicTally {
        bytes32 voteId;
        bytes[] encryptedTotals; // Homomorphically encrypted vote counts
        bool isFinalized;
    }

    // Storage
    mapping(bytes32 => Vote) public votes;
    mapping(bytes32 => VoteOption[]) public voteOptions;
    mapping(bytes32 => EncryptedVote[]) public encryptedVotes;
    mapping(bytes32 => HomomorphicTally) public homomorphicTallies;
    mapping(address => bool) public authorizedHardware;
    
    bytes32[] public activeVotes;
    BiometricVerifier public immutable biometricVerifier;
    HomomorphicTally public immutable homomorphicTally;

    // Events
    event VoteCreated(
        bytes32 indexed voteId,
        string title,
        VoteType voteType,
        uint256 startTime,
        uint256 endTime
    );
    
    event VoteCast(
        bytes32 indexed voteId,
        bytes32 nullifier,
        uint256 timestamp,
        bool isBlind
    );
    
    event VoteEnded(bytes32 indexed voteId, uint256 totalVotes);
    event VoteFinalized(bytes32 indexed voteId, bytes32[] results);
    event HardwareAuthorized(address indexed hardware, bool authorized);

    // Custom errors
    error VoteNotFound();
    error VoteNotActive();
    error VoteAlreadyEnded();
    error AlreadyVoted();
    error UnauthorizedHardware();
    error InvalidTimeRange();
    error InvalidSignature();

    modifier onlyActiveVote(bytes32 voteId) {
        Vote storage vote = votes[voteId];
        if (vote.id == bytes32(0)) revert VoteNotFound();
        if (vote.status != VoteStatus.ACTIVE) revert VoteNotActive();
        if (block.timestamp > vote.endTime) revert VoteAlreadyEnded();
        _;
    }

    modifier onlyAuthorizedHardware() {
        if (!authorizedHardware[msg.sender]) revert UnauthorizedHardware();
        _;
    }

    constructor(address _biometricVerifier, address _homomorphicTally) {
        biometricVerifier = BiometricVerifier(_biometricVerifier);
        homomorphicTally = HomomorphicTally(_homomorphicTally);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Create a new vote
     * @param title Vote title
     * @param description Vote description
     * @param voteType Type of vote (DeFi, NFT, Corporate)
     * @param options Array of vote options
     * @param startTime When voting begins
     * @param endTime When voting ends
     * @param requiresBiometric Whether biometric authentication is required
     * @param allowsBlindVoting Whether blind voting is allowed
     */
    function createVote(
        string memory title,
        string memory description,
        VoteType voteType,
        VoteOption[] memory options,
        uint256 startTime,
        uint256 endTime,
        bool requiresBiometric,
        bool allowsBlindVoting
    ) external onlyRole(VOTE_CREATOR_ROLE) returns (bytes32) {
        require(startTime > block.timestamp, "Start time must be in future");
        require(endTime > startTime, "End time must be after start time");
        require(options.length >= 2, "Must have at least 2 options");
        require(options.length <= 10, "Too many options");

        bytes32 voteId = keccak256(abi.encodePacked(
            title,
            description,
            block.timestamp,
            msg.sender
        ));

        Vote storage newVote = votes[voteId];
        newVote.id = voteId;
        newVote.title = title;
        newVote.description = description;
        newVote.voteType = voteType;
        newVote.status = startTime <= block.timestamp ? VoteStatus.ACTIVE : VoteStatus.CREATED;
        newVote.startTime = startTime;
        newVote.endTime = endTime;
        newVote.creator = msg.sender;
        newVote.requiresBiometric = requiresBiometric;
        newVote.allowsBlindVoting = allowsBlindVoting;

        // Store options
        for (uint256 i = 0; i < options.length; i++) {
            voteOptions[voteId].push(options[i]);
            newVote.options.push(options[i].id);
        }

        if (newVote.status == VoteStatus.ACTIVE) {
            activeVotes.push(voteId);
        }

        emit VoteCreated(voteId, title, voteType, startTime, endTime);
        return voteId;
    }

    /**
     * @dev Cast a biometric-authenticated vote
     * @param voteId Vote identifier
     * @param choiceId Selected option ID
     * @param voterBiometricId Biometric-derived voter ID
     * @param signature Biometric signature
     * @param nullifier Unique nullifier to prevent double voting
     */
    function castBiometricVote(
        bytes32 voteId,
        bytes32 choiceId,
        bytes32 voterBiometricId,
        bytes memory signature,
        bytes32 nullifier
    ) external onlyActiveVote(voteId) nonReentrant {
        Vote storage vote = votes[voteId];
        
        // Check if already voted using nullifier
        if (vote.hasVoted[nullifier]) revert AlreadyVoted();
        
        // Verify nullifier hasn't been used globally
        require(!biometricVerifier.isNullifierUsed(nullifier), "Nullifier already used");

        if (vote.requiresBiometric) {
            // Verify biometric signature
            bytes memory message = abi.encodePacked(voteId, choiceId, nullifier);
            require(
                biometricVerifier.verifyBiometricSignature(
                    voterBiometricId,
                    message,
                    signature
                ),
                "Invalid biometric signature"
            );
        }

        // Verify choice is valid
        bool validChoice = false;
        for (uint256 i = 0; i < vote.options.length; i++) {
            if (vote.options[i] == choiceId) {
                validChoice = true;
                break;
            }
        }
        require(validChoice, "Invalid choice");

        // Record vote
        vote.hasVoted[nullifier] = true;
        vote.optionVotes[choiceId]++;
        vote.totalVotes++;

        // Mark nullifier as used
        biometricVerifier.markNullifierUsed(nullifier);

        emit VoteCast(voteId, nullifier, block.timestamp, false);
    }

    /**
     * @dev Cast a blind vote for maximum privacy
     * @param voteId Vote identifier
     * @param encryptedChoice Homomorphically encrypted choice
     * @param blindSignature Blind signature from hardware
     * @param nullifier Unique nullifier
     * @param zkProof Zero-knowledge proof of eligibility
     */
    function castBlindVote(
        bytes32 voteId,
        bytes memory encryptedChoice,
        bytes memory blindSignature,
        bytes32 nullifier,
        BiometricVerifier.ZKProof memory zkProof
    ) external onlyActiveVote(voteId) nonReentrant {
        Vote storage vote = votes[voteId];
        
        require(vote.allowsBlindVoting, "Blind voting not allowed");
        
        // Check if already voted
        if (vote.hasVoted[nullifier]) revert AlreadyVoted();
        require(!biometricVerifier.isNullifierUsed(nullifier), "Nullifier already used");

        // Verify zero-knowledge proof of voting eligibility
        require(
            biometricVerifier.verifyZKProof(zkProof, nullifier),
            "Invalid ZK proof"
        );

        // Store encrypted vote for homomorphic tallying
        encryptedVotes[voteId].push(EncryptedVote({
            voteId: voteId,
            encryptedChoice: encryptedChoice,
            signature: blindSignature,
            nullifier: nullifier,
            timestamp: block.timestamp
        }));

        // Submit to homomorphic tally contract for real-time encrypted counting
        homomorphicTally.submitEncryptedVote(
            voteId,
            encryptedChoice,
            nullifier,
            abi.encode(zkProof) // Convert ZK proof to bytes
        );

        vote.hasVoted[nullifier] = true;
        vote.totalVotes++;

        // Mark nullifier as used
        biometricVerifier.markNullifierUsed(nullifier);

        emit VoteCast(voteId, nullifier, block.timestamp, true);
    }

    /**
     * @dev End voting and begin tallying
     * @param voteId Vote to end
     */
    function endVote(bytes32 voteId) external {
        Vote storage vote = votes[voteId];
        require(vote.id != bytes32(0), "Vote not found");
        require(
            block.timestamp >= vote.endTime || 
            hasRole(ADMIN_ROLE, msg.sender),
            "Vote period not ended"
        );
        require(vote.status == VoteStatus.ACTIVE, "Vote not active");

        vote.status = VoteStatus.ENDED;

        // Remove from active votes
        for (uint256 i = 0; i < activeVotes.length; i++) {
            if (activeVotes[i] == voteId) {
                activeVotes[i] = activeVotes[activeVotes.length - 1];
                activeVotes.pop();
                break;
            }
        }

        emit VoteEnded(voteId, vote.totalVotes);
    }

    /**
     * @dev Finalize vote results (for blind votes, this includes homomorphic decryption)
     * @param voteId Vote to finalize
     * @param decryptedTallies Decrypted vote tallies (for blind votes)
     */
    function finalizeVote(
        bytes32 voteId,
        uint256[] memory decryptedTallies
    ) external onlyRole(ADMIN_ROLE) {
        Vote storage vote = votes[voteId];
        require(vote.status == VoteStatus.ENDED, "Vote not ended");

        if (vote.allowsBlindVoting && decryptedTallies.length > 0) {
            // Update tallies from homomorphic decryption
            require(decryptedTallies.length == vote.options.length, "Tally count mismatch");
            
            for (uint256 i = 0; i < vote.options.length; i++) {
                vote.optionVotes[vote.options[i]] = decryptedTallies[i];
            }
        }

        vote.status = VoteStatus.FINALIZED;

        emit VoteFinalized(voteId, vote.options);
    }

    /**
     * @dev Get vote results
     * @param voteId Vote identifier
     * @return options Array of option IDs
     * @return tallies Array of vote counts per option
     */
    function getVoteResults(bytes32 voteId) 
        external 
        view 
        returns (bytes32[] memory options, uint256[] memory tallies) 
    {
        Vote storage vote = votes[voteId];
        require(vote.id != bytes32(0), "Vote not found");
        
        options = vote.options;
        tallies = new uint256[](options.length);
        
        for (uint256 i = 0; i < options.length; i++) {
            tallies[i] = vote.optionVotes[options[i]];
        }
    }

    /**
     * @dev Get vote details
     * @param voteId Vote identifier
     */
    function getVoteDetails(bytes32 voteId) 
        external 
        view 
        returns (
            string memory title,
            string memory description,
            VoteType voteType,
            VoteStatus status,
            uint256 startTime,
            uint256 endTime,
            uint256 totalVotes,
            bool requiresBiometric,
            bool allowsBlindVoting
        ) 
    {
        Vote storage vote = votes[voteId];
        require(vote.id != bytes32(0), "Vote not found");
        
        return (
            vote.title,
            vote.description,
            vote.voteType,
            vote.status,
            vote.startTime,
            vote.endTime,
            vote.totalVotes,
            vote.requiresBiometric,
            vote.allowsBlindVoting
        );
    }

    /**
     * @dev Get all active votes
     */
    function getActiveVotes() external view returns (bytes32[] memory) {
        return activeVotes;
    }

    /**
     * @dev Authorize hardware device for voting
     * @param hardware Hardware device address
     * @param authorized Whether to authorize
     */
    function authorizeHardware(address hardware, bool authorized) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        authorizedHardware[hardware] = authorized;
        emit HardwareAuthorized(hardware, authorized);
    }

    /**
     * @dev Emergency pause voting
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause voting
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Check if an address has voted using nullifier
     * @param voteId Vote identifier
     * @param nullifier Nullifier to check
     */
    function hasVotedWithNullifier(bytes32 voteId, bytes32 nullifier) 
        external 
        view 
        returns (bool) 
    {
        return votes[voteId].hasVoted[nullifier];
    }

    /**
     * @dev Get vote options for a specific vote
     * @param voteId Vote identifier
     */
    function getVoteOptions(bytes32 voteId) 
        external 
        view 
        returns (VoteOption[] memory) 
    {
        return voteOptions[voteId];
    }

    /**
     * @dev Get encrypted votes (for homomorphic tallying)
     * @param voteId Vote identifier
     */
    function getEncryptedVotes(bytes32 voteId) 
        external 
        view 
        returns (EncryptedVote[] memory) 
    {
        return encryptedVotes[voteId];
    }
}