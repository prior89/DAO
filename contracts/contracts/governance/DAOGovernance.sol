// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../voting/VotingManager.sol";
import "../crypto/BiometricVerifier.sol";

/**
 * @title DAOGovernance
 * @dev Comprehensive DAO governance system with biometric authentication
 * Supports DeFi protocols, NFT communities, and corporate governance
 */
contract DAOGovernance is 
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl,
    AccessControl
{
    bytes32 public constant PROPOSAL_CREATOR_ROLE = keccak256("PROPOSAL_CREATOR_ROLE");
    bytes32 public constant BIOMETRIC_ADMIN_ROLE = keccak256("BIOMETRIC_ADMIN_ROLE");

    enum GovernanceType {
        DEFI_PROTOCOL,     // DeFi protocol governance
        NFT_COMMUNITY,     // NFT community governance  
        CORPORATE,         // Corporate governance
        HYBRID            // Mixed governance model
    }

    struct ProposalMetadata {
        GovernanceType governanceType;
        string ipfsHash;           // IPFS hash for detailed proposal
        bytes32 category;          // Category of proposal
        uint256 requiredQuorum;    // Custom quorum if different from default
        bool requiresBiometric;    // Whether biometric auth is required
        address proposer;          // Original proposer
        uint256 createdAt;         // Creation timestamp
    }

    struct BiometricVotingParams {
        bool enabled;              // Whether biometric voting is enabled
        uint256 biometricWeight;   // Weight multiplier for biometric votes
        uint256 minimumBiometricParticipation; // Min % of biometric votes required
    }

    struct GovernanceParams {
        uint256 proposalThreshold;    // Tokens needed to create proposal
        uint256 votingDelay;          // Delay before voting starts
        uint256 votingPeriod;         // How long voting lasts
        uint256 quorumNumerator;      // Quorum percentage numerator
        uint256 timelockDelay;        // Timelock delay for execution
    }

    // Storage
    mapping(uint256 => ProposalMetadata) public proposalMetadata;
    mapping(uint256 => BiometricVotingParams) public proposalBiometricParams;
    mapping(GovernanceType => GovernanceParams) public governanceParams;
    mapping(uint256 => mapping(address => bool)) public hasBiometricVoted;
    mapping(uint256 => uint256) public biometricVoteCount;
    
    // Biometric DAO voting rights management system
    mapping(address => uint256) public biometricVotingPower;
    mapping(string => bool) public usedBiometricEligibilityIds;
    mapping(address => uint256[]) private _userBiometricTokens;
    
    VotingManager public immutable votingManager;
    BiometricVerifier public immutable biometricVerifier;
    GovernanceType public immutable governanceType;

    // Events
    event ProposalCreatedWithMetadata(
        uint256 proposalId,
        address proposer,
        GovernanceType governanceType,
        string ipfsHash,
        bool requiresBiometric
    );
    
    event BiometricVoteCast(
        uint256 proposalId,
        address voter,
        bytes32 biometricId,
        uint8 support,
        uint256 weight
    );
    
    event GovernanceParamsUpdated(
        GovernanceType governanceType,
        GovernanceParams params
    );

    event BiometricVotingEnabled(uint256 proposalId, BiometricVotingParams params);
    
    // Biometric DAO voting rights events
    event BiometricVotingRightsMinted(
        uint256 indexed tokenId,
        address indexed voter,
        string biometricEligibilityId,
        uint256 votingPower
    );
    
    event BiometricVotingRightsBurned(uint256 indexed tokenId);
    
    event BiometricVotingRightsTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to
    );

    constructor(
        IVotes _token,
        TimelockController _timelock,
        VotingManager _votingManager,
        BiometricVerifier _biometricVerifier,
        GovernanceType _governanceType
    )
        Governor("BiometricDAO")
        GovernorSettings(1, 50400, 1e18) // 1 block delay, ~1 week voting, 1 token threshold
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4) // 4% quorum
        GovernorTimelockControl(_timelock)
    {
        votingManager = _votingManager;
        biometricVerifier = _biometricVerifier;
        governanceType = _governanceType;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROPOSAL_CREATOR_ROLE, msg.sender);
        _grantRole(BIOMETRIC_ADMIN_ROLE, msg.sender);

        // Initialize default governance parameters
        _initializeGovernanceParams();
    }

    /**
     * @dev Create proposal with biometric authentication support
     * @param targets Target addresses for proposal calls
     * @param values ETH values for each call
     * @param calldatas Call data for each target
     * @param description Proposal description
     * @param governanceTypeProposal Type of governance for this proposal
     * @param ipfsHash IPFS hash for detailed proposal
     * @param requiresBiometric Whether biometric authentication is required
     * @param biometricParams Parameters for biometric voting
     */
    function proposeWithBiometric(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        GovernanceType governanceTypeProposal,
        string memory ipfsHash,
        bool requiresBiometric,
        BiometricVotingParams memory biometricParams
    ) public onlyRole(PROPOSAL_CREATOR_ROLE) returns (uint256) {
        
        uint256 proposalId = propose(targets, values, calldatas, description);
        
        // Store proposal metadata
        proposalMetadata[proposalId] = ProposalMetadata({
            governanceType: governanceTypeProposal,
            ipfsHash: ipfsHash,
            category: keccak256(abi.encodePacked(governanceTypeProposal)),
            requiredQuorum: quorumNumerator(),
            requiresBiometric: requiresBiometric,
            proposer: msg.sender,
            createdAt: block.timestamp
        });

        if (requiresBiometric) {
            proposalBiometricParams[proposalId] = biometricParams;
            emit BiometricVotingEnabled(proposalId, biometricParams);
        }

        emit ProposalCreatedWithMetadata(
            proposalId,
            msg.sender,
            governanceTypeProposal,
            ipfsHash,
            requiresBiometric
        );

        return proposalId;
    }

    /**
     * @dev Cast vote with biometric authentication
     * @param proposalId Proposal to vote on
     * @param support Vote choice (0=against, 1=for, 2=abstain)
     * @param biometricId Biometric-derived voter ID
     * @param signature Biometric signature
     * @param reason Vote reasoning
     */
    function castBiometricVote(
        uint256 proposalId,
        uint8 support,
        bytes32 biometricId,
        bytes memory signature,
        string memory reason
    ) public returns (uint256) {
        ProposalMetadata memory metadata = proposalMetadata[proposalId];
        require(metadata.requiresBiometric, "Proposal doesn't require biometric auth");
        require(!hasBiometricVoted[proposalId][msg.sender], "Already voted with biometrics");

        // Verify biometric signature
        bytes memory message = abi.encodePacked(proposalId, support, msg.sender);
        require(
            biometricVerifier.verifyBiometricSignature(biometricId, message, signature),
            "Invalid biometric signature"
        );

        // Mark as biometric voted
        hasBiometricVoted[proposalId][msg.sender] = true;
        biometricVoteCount[proposalId]++;

        // Cast vote with potential weight bonus
        BiometricVotingParams memory biometricParams = proposalBiometricParams[proposalId];
        uint256 weight = getVotes(msg.sender, proposalSnapshot(proposalId));
        
        if (biometricParams.biometricWeight > 100) {
            weight = (weight * biometricParams.biometricWeight) / 100;
        }

        // Use internal voting mechanism with adjusted weight
        return _castVote(proposalId, msg.sender, support, reason, weight);

        emit BiometricVoteCast(proposalId, msg.sender, biometricId, support, weight);
    }

    /**
     * @dev Cast anonymous vote using zero-knowledge proof
     * @param proposalId Proposal to vote on
     * @param support Vote choice
     * @param zkProof Zero-knowledge proof of voting eligibility
     * @param nullifier Unique nullifier to prevent double voting
     */
    function castAnonymousVote(
        uint256 proposalId,
        uint8 support,
        BiometricVerifier.ZKProof memory zkProof,
        bytes32 nullifier
    ) public {
        require(
            state(proposalId) == ProposalState.Active,
            "Proposal not active"
        );

        // Verify ZK proof
        require(
            biometricVerifier.verifyZKProof(zkProof, nullifier),
            "Invalid ZK proof"
        );

        // Check nullifier hasn't been used
        require(
            !biometricVerifier.isNullifierUsed(nullifier),
            "Nullifier already used"
        );

        // Mark nullifier as used
        biometricVerifier.markNullifierUsed(nullifier);

        // Cast anonymous vote (weight = 1 for privacy)
        _castVote(proposalId, address(0), support, "", 1e18);
    }

    /**
     * @dev Check if proposal meets biometric participation requirements
     * @param proposalId Proposal to check
     */
    function _checkBiometricParticipation(uint256 proposalId) internal view returns (bool) {
        BiometricVotingParams memory params = proposalBiometricParams[proposalId];
        
        if (!params.enabled) {
            return true; // No biometric requirement
        }

        uint256 totalVotes = proposalVotes(proposalId).forVotes + 
                           proposalVotes(proposalId).againstVotes + 
                           proposalVotes(proposalId).abstainVotes;
        
        if (totalVotes == 0) {
            return false;
        }

        uint256 biometricPercentage = (biometricVoteCount[proposalId] * 100) / totalVotes;
        return biometricPercentage >= params.minimumBiometricParticipation;
    }

    /**
     * @dev Override quorum calculation to include biometric requirements
     */
    function _quorumReached(uint256 proposalId) internal view override returns (bool) {
        // Check standard quorum
        bool standardQuorum = super._quorumReached(proposalId);
        
        // Check biometric participation if required
        bool biometricQuorum = _checkBiometricParticipation(proposalId);
        
        return standardQuorum && biometricQuorum;
    }

    /**
     * @dev Update governance parameters for specific governance type
     * @param govType Governance type to update
     * @param params New parameters
     */
    function updateGovernanceParams(
        GovernanceType govType,
        GovernanceParams memory params
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        governanceParams[govType] = params;
        emit GovernanceParamsUpdated(govType, params);
    }

    /**
     * @dev Get proposal metadata
     * @param proposalId Proposal identifier
     */
    function getProposalMetadata(uint256 proposalId) 
        external 
        view 
        returns (ProposalMetadata memory) 
    {
        return proposalMetadata[proposalId];
    }

    /**
     * @dev Get biometric voting parameters for proposal
     * @param proposalId Proposal identifier
     */
    function getBiometricVotingParams(uint256 proposalId)
        external
        view
        returns (BiometricVotingParams memory)
    {
        return proposalBiometricParams[proposalId];
    }

    /**
     * @dev Check if address has voted with biometrics
     * @param proposalId Proposal identifier
     * @param voter Voter address
     */
    function hasVotedWithBiometrics(uint256 proposalId, address voter)
        external
        view
        returns (bool)
    {
        return hasBiometricVoted[proposalId][voter];
    }

    // Required overrides
    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor, GovernorTimelockControl, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        uint256 weight
    ) internal returns (uint256) {
        return super._castVote(proposalId, account, support, reason);
    }

    /**
     * @dev Mint biometric voting rights for DAO governance
     * @param to Address to receive voting rights
     * @param voterCategory Category of voter ("DAO_MEMBER", "STAKEHOLDER")
     * @param biometricEligibilityId Unique biometric eligibility identifier
     * @param votingPower Voting weight based on biometric authentication
     */
    function mintBiometricVotingRights(
        address to,
        string memory voterCategory,
        string memory biometricEligibilityId,
        uint256 votingPower
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bytes(biometricEligibilityId).length > 0, "Biometric eligibility ID required");
        require(!usedBiometricEligibilityIds[biometricEligibilityId], "Biometric eligibility ID already used");
        require(votingPower > 0, "Voting power must be positive");
        
        // Mark biometric eligibility ID as used
        usedBiometricEligibilityIds[biometricEligibilityId] = true;
        
        // Add to user's biometric voting power
        biometricVotingPower[to] += votingPower;
        
        // Track user biometric voting tokens
        uint256 tokenCount = _userBiometricTokens[to].length;
        _userBiometricTokens[to].push(tokenCount + 1);
        
        emit BiometricVotingRightsMinted(
            tokenCount + 1,
            to,
            biometricEligibilityId,
            votingPower
        );
    }

    /**
     * @dev Burn biometric voting rights for security
     * @param voter Address to remove voting rights from
     * @param biometricEligibilityId Biometric eligibility ID to burn
     */
    function burnBiometricVotingRights(
        address voter,
        string memory biometricEligibilityId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(usedBiometricEligibilityIds[biometricEligibilityId], "Biometric eligibility ID not found");
        require(biometricVotingPower[voter] > 0, "No biometric voting power to burn");
        
        // Reset biometric voting power
        biometricVotingPower[voter] = 0;
        
        // Clear user biometric tokens
        delete _userBiometricTokens[voter];
        
        // Mark biometric eligibility as available again
        usedBiometricEligibilityIds[biometricEligibilityId] = false;
        
        emit BiometricVotingRightsBurned(0); // Placeholder token ID
    }

    /**
     * @dev Get user's biometric voting power
     * @param user User address
     */
    function getUserBiometricVotingPower(address user) external view returns (uint256) {
        return biometricVotingPower[user];
    }

    /**
     * @dev Transfer biometric voting rights with privacy protection
     * @param from Current holder
     * @param to New holder  
     * @param biometricEligibilityId Biometric eligibility ID to transfer
     */
    function transferBiometricVotingRightsWithPrivacy(
        address from,
        address to,
        string memory biometricEligibilityId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(biometricVotingPower[from] > 0, "No biometric voting power to transfer");
        require(usedBiometricEligibilityIds[biometricEligibilityId], "Invalid biometric eligibility ID");
        
        uint256 votingPower = biometricVotingPower[from];
        
        // Burn from source (privacy protection)
        biometricVotingPower[from] = 0;
        delete _userBiometricTokens[from];
        
        // Mint to destination (fresh identity)
        biometricVotingPower[to] = votingPower;
        _userBiometricTokens[to].push(_userBiometricTokens[to].length + 1);
        
        emit BiometricVotingRightsTransferred(0, from, to);
    }

    function _initializeGovernanceParams() private {
        // DeFi Protocol defaults
        governanceParams[GovernanceType.DEFI_PROTOCOL] = GovernanceParams({
            proposalThreshold: 1e18,     // 1 token
            votingDelay: 1,              // 1 block
            votingPeriod: 50400,         // ~1 week
            quorumNumerator: 4,          // 4%
            timelockDelay: 172800        // 2 days
        });

        // NFT Community defaults
        governanceParams[GovernanceType.NFT_COMMUNITY] = GovernanceParams({
            proposalThreshold: 1e17,     // 0.1 token
            votingDelay: 7200,           // ~1 day
            votingPeriod: 100800,        // ~2 weeks
            quorumNumerator: 3,          // 3%
            timelockDelay: 86400         // 1 day
        });

        // Corporate defaults
        governanceParams[GovernanceType.CORPORATE] = GovernanceParams({
            proposalThreshold: 1e19,     // 10 tokens
            votingDelay: 14400,          // ~2 days
            votingPeriod: 201600,        // ~1 month
            quorumNumerator: 10,         // 10%
            timelockDelay: 604800        // 1 week
        });

        // Hybrid defaults
        governanceParams[GovernanceType.HYBRID] = GovernanceParams({
            proposalThreshold: 5e18,     // 5 tokens
            votingDelay: 7200,           // ~1 day
            votingPeriod: 100800,        // ~2 weeks
            quorumNumerator: 5,          // 5%
            timelockDelay: 259200        // 3 days
        });
    }
}