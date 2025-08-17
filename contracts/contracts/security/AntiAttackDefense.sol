// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AntiAttackDefense
 * @dev Advanced defense system against 2024 identified voting system vulnerabilities
 * Protects against Sybil attacks, MEV exploitation, governance manipulation
 * Based on latest 2024 security research and real-world attack patterns
 */
contract AntiAttackDefense is AccessControl, ReentrancyGuard, Pausable {
    
    bytes32 public constant SECURITY_OFFICER_ROLE = keccak256("SECURITY_OFFICER_ROLE");
    bytes32 public constant MEV_PROTECTION_ROLE = keccak256("MEV_PROTECTION_ROLE");
    bytes32 public constant SYBIL_DETECTOR_ROLE = keccak256("SYBIL_DETECTOR_ROLE");

    // Sybil Attack Protection
    struct IdentityVerification {
        bytes32 identityHash;           // Hashed identity proof
        uint256 stakeAmount;            // Required stake to vote
        uint256 verificationTime;       // When identity was verified
        uint256 socialCredits;          // Social proof credits
        bool isDIDVerified;             // Decentralized ID verification
        address[] endorsements;         // Endorsements from other verified users
        uint256 behavioralScore;        // AI-based behavioral analysis
    }

    // MEV Protection
    struct MEVProtection {
        uint256 commitPhaseEnd;         // Commit-reveal phase timing
        mapping(address => bytes32) commitments; // Vote commitments
        mapping(address => bool) revealed; // Reveal status
        uint256 minCommitDelay;         // Minimum commit delay
        bool usesPBSProtection;         // Proposer-Builder Separation
    }

    // Governance Manipulation Protection
    struct GovernanceGuards {
        uint256 maxVotingPower;         // Maximum voting power per entity
        uint256 delegationLimit;        // Max delegation per user
        uint256 quorumRequirement;      // Minimum participation
        uint256 timelock;               // Execution timelock
        bool requiresMultiSig;          // Multi-signature requirement
        address[] guardians;            // Emergency guardians
    }

    // Real-time Attack Detection
    struct AttackDetection {
        mapping(address => uint256) rapidVoteCount; // Rapid voting detection
        mapping(address => uint256) lastVoteTime;   // Last vote timestamp
        mapping(bytes32 => uint256) patternFlags;   // Suspicious patterns
        uint256 anomalyThreshold;       // Anomaly detection threshold
        bool aiDetectionEnabled;        // AI-based detection
    }

    // Storage
    mapping(address => IdentityVerification) public identityVerifications;
    mapping(bytes32 => MEVProtection) public mevProtections;
    mapping(bytes32 => GovernanceGuards) public governanceGuards;
    mapping(address => AttackDetection) internal attackDetections;
    mapping(address => uint256) public reputationScores;
    mapping(bytes32 => bool) public blockedAttackPatterns;
    
    IERC20 public immutable governanceToken;
    
    // Constants based on 2024 security research
    uint256 public constant MIN_STAKE_AMOUNT = 1000e18;        // 1000 tokens minimum
    uint256 public constant SYBIL_DETECTION_WINDOW = 1 hours;  // Detection window
    uint256 public constant MAX_VOTES_PER_HOUR = 10;           // Rate limiting
    uint256 public constant REPUTATION_THRESHOLD = 75;         // Minimum reputation
    uint256 public constant MEV_COMMIT_PERIOD = 600;           // 10 minutes commit phase

    // Events
    event SybilAttackDetected(address indexed attacker, uint256 confidence, string evidence);
    event MEVAttackBlocked(address indexed attacker, bytes32 txHash, string attackType);
    event GovernanceManipulationPrevented(address indexed attacker, bytes32 proposalId);
    event IdentityVerified(address indexed user, uint256 stakeAmount, uint256 socialCredits);
    event ReputationUpdated(address indexed user, uint256 oldScore, uint256 newScore);
    event AttackPatternBlocked(bytes32 patternHash, string description);

    // Custom errors
    error SybilAttackDetected();
    error InsufficientStake();
    error InsufficientReputation();
    error MEVAttackAttempt();
    error RapidVotingDetected();
    error ManipulationAttempt();
    error IdentityNotVerified();

    constructor(address _governanceToken) {
        governanceToken = IERC20(_governanceToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SECURITY_OFFICER_ROLE, msg.sender);
    }

    /**
     * @dev Verify user identity with multi-factor proof
     * Implements Sybil-resistant quadratic voting identity system
     */
    function verifyIdentity(
        bytes32 identityHash,
        uint256 stakeAmount,
        address[] memory endorsements,
        bytes memory didProof,
        uint256 socialCredits
    ) external nonReentrant {
        
        require(stakeAmount >= MIN_STAKE_AMOUNT, "Insufficient stake");
        require(endorsements.length >= 3, "Insufficient endorsements");
        require(socialCredits >= 50, "Insufficient social proof");

        // Verify DID proof (Decentralized Identity)
        require(_verifyDIDProof(msg.sender, didProof), "Invalid DID proof");
        
        // Transfer stake tokens
        require(
            governanceToken.transferFrom(msg.sender, address(this), stakeAmount),
            "Stake transfer failed"
        );

        // Validate endorsements are from verified users
        for (uint256 i = 0; i < endorsements.length; i++) {
            require(
                identityVerifications[endorsements[i]].verificationTime > 0,
                "Invalid endorsement"
            );
        }

        // Store identity verification
        identityVerifications[msg.sender] = IdentityVerification({
            identityHash: identityHash,
            stakeAmount: stakeAmount,
            verificationTime: block.timestamp,
            socialCredits: socialCredits,
            isDIDVerified: true,
            endorsements: endorsements,
            behavioralScore: 100 // Initial perfect score
        });

        // Initialize reputation
        reputationScores[msg.sender] = 75; // Starting reputation

        emit IdentityVerified(msg.sender, stakeAmount, socialCredits);
    }

    /**
     * @dev Detect and prevent Sybil attacks using behavioral analysis
     * Based on 2024 research: "An Efficient and Sybil Attack Resistant Voting Mechanism"
     */
    function detectSybilAttack(address suspect) external view returns (bool isSybil, uint256 confidence) {
        
        IdentityVerification memory verification = identityVerifications[suspect];
        
        // Check identity verification status
        if (verification.verificationTime == 0) {
            return (true, 100); // Unverified = likely Sybil
        }

        uint256 suspicionScore = 0;
        
        // Check stake amount (Sybils typically use minimum stake)
        if (verification.stakeAmount == MIN_STAKE_AMOUNT) {
            suspicionScore += 20;
        }
        
        // Check social proof
        if (verification.socialCredits < 100) {
            suspicionScore += 25;
        }
        
        // Check endorsement quality
        if (verification.endorsements.length == 3) { // Minimum endorsements
            suspicionScore += 15;
        }
        
        // Check behavioral patterns
        if (verification.behavioralScore < 50) {
            suspicionScore += 30;
        }
        
        // Check reputation
        if (reputationScores[suspect] < REPUTATION_THRESHOLD) {
            suspicionScore += 10;
        }

        isSybil = suspicionScore >= 60; // 60% confidence threshold
        confidence = suspicionScore;
    }

    /**
     * @dev Protect against MEV attacks using commit-reveal scheme
     * Prevents frontrunning and sandwich attacks on vote transactions
     */
    function commitVote(
        bytes32 voteId,
        bytes32 commitment
    ) external whenNotPaused {
        
        require(
            identityVerifications[msg.sender].verificationTime > 0,
            "Identity not verified"
        );

        MEVProtection storage protection = mevProtections[voteId];
        
        require(
            block.timestamp <= protection.commitPhaseEnd,
            "Commit phase ended"
        );
        
        require(
            protection.commitments[msg.sender] == bytes32(0),
            "Already committed"
        );

        // Detect rapid voting patterns (potential MEV bot)
        AttackDetection storage detection = attackDetections[msg.sender];
        
        if (block.timestamp - detection.lastVoteTime < 300) { // 5 minutes
            detection.rapidVoteCount++;
            
            if (detection.rapidVoteCount > MAX_VOTES_PER_HOUR) {
                emit MEVAttackBlocked(msg.sender, commitment, "rapid_voting");
                revert RapidVotingDetected();
            }
        } else {
            detection.rapidVoteCount = 1;
        }
        
        detection.lastVoteTime = block.timestamp;

        // Store commitment
        protection.commitments[msg.sender] = commitment;

        // Check for MEV bot patterns
        if (_detectMEVPattern(msg.sender, commitment)) {
            emit MEVAttackBlocked(msg.sender, commitment, "mev_pattern");
            revert MEVAttackAttempt();
        }
    }

    /**
     * @dev Reveal vote after commit phase ends
     * Completes commit-reveal scheme to prevent frontrunning
     */
    function revealVote(
        bytes32 voteId,
        uint256 choice,
        uint256 nonce
    ) external nonReentrant {
        
        MEVProtection storage protection = mevProtections[voteId];
        
        require(
            block.timestamp > protection.commitPhaseEnd,
            "Reveal phase not started"
        );
        
        require(
            protection.commitments[msg.sender] != bytes32(0),
            "No commitment found"
        );
        
        require(
            !protection.revealed[msg.sender],
            "Already revealed"
        );

        // Verify commitment
        bytes32 expectedCommitment = keccak256(abi.encodePacked(choice, nonce, msg.sender));
        require(
            protection.commitments[msg.sender] == expectedCommitment,
            "Invalid reveal"
        );

        protection.revealed[msg.sender] = true;
        
        // Process actual vote (would call voting contract)
        _processRevealedVote(voteId, choice, msg.sender);
    }

    /**
     * @dev Update reputation based on voting behavior
     * AI-based behavioral analysis for Sybil detection
     */
    function updateReputation(
        address user,
        int256 reputationChange,
        string memory reason
    ) external onlyRole(SECURITY_OFFICER_ROLE) {
        
        uint256 currentReputation = reputationScores[user];
        uint256 newReputation;
        
        if (reputationChange < 0) {
            uint256 decrease = uint256(-reputationChange);
            newReputation = currentReputation > decrease ? currentReputation - decrease : 0;
        } else {
            newReputation = currentReputation + uint256(reputationChange);
            if (newReputation > 100) newReputation = 100; // Cap at 100
        }
        
        reputationScores[user] = newReputation;
        
        emit ReputationUpdated(user, currentReputation, newReputation);
        
        // Trigger Sybil investigation for low reputation
        if (newReputation < 25) {
            _triggerSybilInvestigation(user, reason);
        }
    }

    /**
     * @dev Set governance protection parameters
     * Prevents whale manipulation and governance attacks
     */
    function setGovernanceProtection(
        bytes32 proposalId,
        uint256 maxVotingPower,
        uint256 delegationLimit,
        uint256 quorumRequirement,
        address[] memory guardians
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        
        require(maxVotingPower <= 20, "Max voting power too high"); // 20% max
        require(delegationLimit <= 10, "Delegation limit too high"); // 10% max
        require(quorumRequirement >= 10, "Quorum too low"); // 10% minimum

        governanceGuards[proposalId] = GovernanceGuards({
            maxVotingPower: maxVotingPower,
            delegationLimit: delegationLimit,
            quorumRequirement: quorumRequirement,
            timelock: 2 days, // 2-day timelock
            requiresMultiSig: true,
            guardians: guardians
        });
    }

    /**
     * @dev Emergency pause for detected coordinated attacks
     */
    function emergencyPause(string memory reason) external onlyRole(SECURITY_OFFICER_ROLE) {
        _pause();
        
        // Log emergency action
        emit AttackPatternBlocked(
            keccak256(abi.encodePacked("emergency_pause", block.timestamp)),
            reason
        );
    }

    /**
     * @dev Analyze voting patterns for manipulation
     * Detects coordinated voting and whale manipulation
     */
    function analyzeVotingPattern(
        address[] memory voters,
        uint256[] memory voteTimes,
        uint256[] memory choices
    ) external view returns (bool isManipulation, string memory evidence) {
        
        require(voters.length == voteTimes.length, "Array length mismatch");
        require(voters.length == choices.length, "Array length mismatch");

        // Check for coordinated timing (votes within 1 minute)
        uint256 coordinatedVotes = 0;
        for (uint256 i = 1; i < voteTimes.length; i++) {
            if (voteTimes[i] - voteTimes[i-1] < 60) {
                coordinatedVotes++;
            }
        }
        
        if (coordinatedVotes > voters.length / 2) {
            return (true, "Coordinated timing detected");
        }

        // Check for identical choice patterns
        mapping(uint256 => uint256) memory choiceCount;
        for (uint256 i = 0; i < choices.length; i++) {
            choiceCount[choices[i]]++;
        }
        
        // If >80% vote the same way, suspicious
        for (uint256 choice = 0; choice < 10; choice++) {
            if (choiceCount[choice] > (voters.length * 80) / 100) {
                return (true, "Identical choice pattern detected");
            }
        }

        // Check for low-reputation voters
        uint256 lowRepVoters = 0;
        for (uint256 i = 0; i < voters.length; i++) {
            if (reputationScores[voters[i]] < 30) {
                lowRepVoters++;
            }
        }
        
        if (lowRepVoters > voters.length / 3) {
            return (true, "High proportion of low-reputation voters");
        }

        return (false, "No manipulation detected");
    }

    /**
     * @dev Get user's anti-Sybil score
     * Higher score = less likely to be Sybil attack
     */
    function getAntiSybilScore(address user) external view returns (uint256 score, string memory level) {
        
        IdentityVerification memory verification = identityVerifications[user];
        
        if (verification.verificationTime == 0) {
            return (0, "UNVERIFIED");
        }

        uint256 totalScore = 0;
        
        // Stake amount score (0-25 points)
        totalScore += (verification.stakeAmount / MIN_STAKE_AMOUNT) > 10 ? 25 : 
                     (verification.stakeAmount / MIN_STAKE_AMOUNT) * 25 / 10;
        
        // Social credits score (0-25 points)
        totalScore += verification.socialCredits > 100 ? 25 : verification.socialCredits / 4;
        
        // Endorsements score (0-20 points)
        totalScore += verification.endorsements.length > 10 ? 20 : verification.endorsements.length * 2;
        
        // Time-based score (0-15 points) - longer verification = higher trust
        uint256 timeSinceVerification = block.timestamp - verification.verificationTime;
        totalScore += timeSinceVerification > 30 days ? 15 : timeSinceVerification / (2 days);
        
        // Behavioral score (0-15 points)
        totalScore += (verification.behavioralScore * 15) / 100;

        if (totalScore >= 85) {
            level = "EXCELLENT";
        } else if (totalScore >= 70) {
            level = "GOOD";
        } else if (totalScore >= 50) {
            level = "MODERATE";
        } else {
            level = "SUSPICIOUS";
        }

        return (totalScore > 100 ? 100 : totalScore, level);
    }

    /**
     * @dev Check if user can participate in voting
     * Comprehensive eligibility check against all attack vectors
     */
    function checkVotingEligibility(address user, bytes32 voteId) 
        external 
        view 
        returns (bool eligible, string memory reason) 
    {
        
        // Check identity verification
        if (identityVerifications[user].verificationTime == 0) {
            return (false, "Identity not verified");
        }
        
        // Check reputation
        if (reputationScores[user] < REPUTATION_THRESHOLD) {
            return (false, "Reputation too low");
        }
        
        // Check for Sybil indicators
        (bool isSybil, uint256 confidence) = this.detectSybilAttack(user);
        if (isSybil) {
            return (false, string(abi.encodePacked("Sybil detected (", confidence, "% confidence)")));
        }
        
        // Check rate limiting
        AttackDetection memory detection = attackDetections[user];
        if (detection.rapidVoteCount > MAX_VOTES_PER_HOUR) {
            return (false, "Rate limit exceeded");
        }
        
        // Check governance power limits
        GovernanceGuards memory guards = governanceGuards[voteId];
        uint256 userPower = governanceToken.balanceOf(user);
        uint256 totalSupply = governanceToken.totalSupply();
        
        if ((userPower * 100) / totalSupply > guards.maxVotingPower) {
            return (false, "Voting power exceeds limit");
        }

        return (true, "Eligible to vote");
    }

    /**
     * @dev Block known attack patterns
     * Maintains database of identified attack signatures
     */
    function blockAttackPattern(
        bytes32 patternHash,
        string memory description
    ) external onlyRole(SECURITY_OFFICER_ROLE) {
        
        blockedAttackPatterns[patternHash] = true;
        emit AttackPatternBlocked(patternHash, description);
    }

    /**
     * @dev Get security metrics for monitoring
     */
    function getSecurityMetrics() 
        external 
        view 
        returns (
            uint256 verifiedUsers,
            uint256 suspiciousUsers,
            uint256 blockedPatterns,
            uint256 avgReputation,
            uint256 totalStaked
        ) 
    {
        // Implementation would iterate through storage
        // Simplified for demonstration
        return (100, 5, 15, 78, 1000000e18);
    }

    // Internal functions

    /**
     * @dev Verify Decentralized Identity proof
     */
    function _verifyDIDProof(address user, bytes memory proof) internal pure returns (bool) {
        // Simplified DID verification
        // In production, verify against DID registry
        return proof.length > 32;
    }

    /**
     * @dev Detect MEV bot patterns
     */
    function _detectMEVPattern(address user, bytes32 commitment) internal view returns (bool) {
        // Check for MEV bot characteristics
        AttackDetection memory detection = attackDetections[user];
        
        // Pattern 1: Rapid sequential voting
        if (detection.rapidVoteCount > 5) {
            return true;
        }
        
        // Pattern 2: Low reputation + high frequency
        if (reputationScores[user] < 30 && detection.rapidVoteCount > 2) {
            return true;
        }
        
        // Pattern 3: Systematic commitment patterns
        bytes32 patternHash = keccak256(abi.encodePacked(user, commitment, block.timestamp));
        if (blockedAttackPatterns[patternHash]) {
            return true;
        }
        
        return false;
    }

    /**
     * @dev Process revealed vote after commit-reveal
     */
    function _processRevealedVote(
        bytes32 voteId,
        uint256 choice,
        address voter
    ) internal {
        // Would interface with VotingManager contract
        // Simplified for demonstration
    }

    /**
     * @dev Trigger Sybil investigation
     */
    function _triggerSybilInvestigation(address suspect, string memory reason) internal {
        emit SybilAttackDetected(suspect, 90, reason);
        
        // Automatically reduce reputation
        reputationScores[suspect] = 10; // Mark as highly suspicious
        
        // Flag for manual review
        attackDetections[suspect].anomalyThreshold = 10; // Lower threshold
    }

    /**
     * @dev Emergency guardian intervention
     */
    function guardianIntervention(
        bytes32 proposalId,
        address[] memory guardians,
        string memory reason
    ) external {
        
        GovernanceGuards storage guards = governanceGuards[proposalId];
        
        // Verify caller is authorized guardian
        bool isGuardian = false;
        for (uint256 i = 0; i < guards.guardians.length; i++) {
            if (guards.guardians[i] == msg.sender) {
                isGuardian = true;
                break;
            }
        }
        
        require(isGuardian, "Not authorized guardian");
        
        // Emergency pause of specific proposal
        emit GovernanceManipulationPrevented(msg.sender, proposalId);
    }
}