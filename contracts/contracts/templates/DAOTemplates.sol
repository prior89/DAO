// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../voting/VotingManager.sol";
import "../governance/DAOGovernance.sol";

/**
 * @title DAOTemplates
 * @dev Template system for different DAO governance types
 * Supports DeFi protocols, NFT communities, and corporate governance
 * Based on 2024 governance best practices and biometric voting integration
 */
contract DAOTemplates is AccessControl, ReentrancyGuard {
    
    bytes32 public constant TEMPLATE_ADMIN_ROLE = keccak256("TEMPLATE_ADMIN_ROLE");
    bytes32 public constant DAO_CREATOR_ROLE = keccak256("DAO_CREATOR_ROLE");

    enum TemplateType {
        DEFI_PROTOCOL,          // DeFi protocol governance
        NFT_COMMUNITY,          // NFT community governance
        CORPORATE_GOVERNANCE,   // Traditional corporate governance
        HYBRID_DAO,            // Mixed governance model
        CUSTOM                 // Custom template
    }

    enum ProposalCategory {
        PARAMETER_CHANGE,       // Protocol parameter changes
        TREASURY_ALLOCATION,    // Treasury fund allocation
        PROTOCOL_UPGRADE,       // Smart contract upgrades
        PARTNERSHIP,           // Strategic partnerships
        COMMUNITY_INITIATIVE,  // Community programs
        EMERGENCY_ACTION,      // Emergency proposals
        CONSTITUTIONAL_CHANGE  // Fundamental governance changes
    }

    struct GovernanceTemplate {
        TemplateType templateType;
        string name;
        string description;
        GovernanceParameters parameters;
        BiometricRequirements biometricReqs;
        VotingConfiguration votingConfig;
        bool isActive;
        address creator;
        uint256 createdAt;
        uint256 usage; // How many DAOs use this template
    }

    struct GovernanceParameters {
        uint256 proposalThreshold;      // Tokens needed to create proposal
        uint256 votingDelay;           // Delay before voting starts (blocks)
        uint256 votingPeriod;          // Voting duration (blocks)  
        uint256 quorumNumerator;       // Quorum percentage (basis points)
        uint256 timelockDelay;         // Execution delay (seconds)
        uint256 vetoThreshold;         // Threshold for veto power
        bool requiresSuperMajority;   // Requires 2/3 majority
    }

    struct BiometricRequirements {
        bool mandatoryForProposals;    // Biometric required for proposals
        bool mandatoryForVoting;       // Biometric required for voting
        uint256 minimumBiometricParticipation; // Min % biometric votes
        uint256 biometricWeightMultiplier;     // Vote weight bonus for biometric
        bool allowsAnonymousVoting;    // Supports zero-knowledge voting
    }

    struct VotingConfiguration {
        bool supportsBlindVoting;      // Supports homomorphic encryption
        bool requiresZKProofs;         // Requires zero-knowledge proofs
        uint256 maxVoteOptions;        // Maximum number of vote options
        bool allowsDelegation;         // Supports vote delegation
        bool allowsRevocation;         // Allows vote revocation
        uint256 participationReward;   // Rewards for participation
    }

    struct DAOInstance {
        bytes32 templateId;
        address daoGovernance;
        address votingManager;
        address treasury;
        string name;
        string description;
        TemplateType daoType;
        address[] founders;
        uint256 totalMembers;
        uint256 createdAt;
        bool isActive;
        mapping(address => bool) isMember;
        mapping(address => uint256) membershipLevel; // 0=basic, 1=premium, 2=admin
    }

    // Storage
    mapping(bytes32 => GovernanceTemplate) public templates;
    mapping(bytes32 => DAOInstance) public daoInstances;
    mapping(TemplateType => bytes32[]) public templatesByType;
    mapping(address => bytes32[]) public daosByCreator;
    
    bytes32[] public allTemplates;
    bytes32[] public allDAOs;
    
    VotingManager public immutable votingManager;
    
    // Events
    event TemplateCreated(
        bytes32 indexed templateId,
        TemplateType indexed templateType,
        string name,
        address creator
    );
    
    event TemplateUpdated(bytes32 indexed templateId, address updater);
    
    event DAOCreated(
        bytes32 indexed daoId,
        bytes32 indexed templateId,
        string name,
        address governance,
        address creator
    );
    
    event DAOMemberAdded(bytes32 indexed daoId, address member, uint256 level);
    event DAOMemberRemoved(bytes32 indexed daoId, address member);
    event TemplateUsageUpdated(bytes32 indexed templateId, uint256 newUsage);

    constructor(address _votingManager) {
        votingManager = VotingManager(_votingManager);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(TEMPLATE_ADMIN_ROLE, msg.sender);
        _grantRole(DAO_CREATOR_ROLE, msg.sender);
        
        // Create default templates
        _createDefaultTemplates();
    }

    /**
     * @dev Create a new governance template
     */
    function createTemplate(
        TemplateType templateType,
        string memory name,
        string memory description,
        GovernanceParameters memory parameters,
        BiometricRequirements memory biometricReqs,
        VotingConfiguration memory votingConfig
    ) external onlyRole(TEMPLATE_ADMIN_ROLE) returns (bytes32) {
        
        bytes32 templateId = keccak256(abi.encodePacked(
            name,
            description,
            templateType,
            block.timestamp,
            msg.sender
        ));

        require(templates[templateId].createdAt == 0, "Template already exists");

        templates[templateId] = GovernanceTemplate({
            templateType: templateType,
            name: name,
            description: description,
            parameters: parameters,
            biometricReqs: biometricReqs,
            votingConfig: votingConfig,
            isActive: true,
            creator: msg.sender,
            createdAt: block.timestamp,
            usage: 0
        });

        allTemplates.push(templateId);
        templatesByType[templateType].push(templateId);

        emit TemplateCreated(templateId, templateType, name, msg.sender);
        return templateId;
    }

    /**
     * @dev Create a new DAO instance from template
     */
    function createDAO(
        bytes32 templateId,
        string memory daoName,
        string memory daoDescription,
        address[] memory founders,
        address treasury
    ) external onlyRole(DAO_CREATOR_ROLE) returns (bytes32) {
        
        GovernanceTemplate storage template = templates[templateId];
        require(template.isActive, "Template not active");

        bytes32 daoId = keccak256(abi.encodePacked(
            daoName,
            templateId,
            block.timestamp,
            msg.sender
        ));

        require(daoInstances[daoId].createdAt == 0, "DAO already exists");

        // Deploy governance contract (simplified - in production deploy actual contracts)
        address governanceAddress = _deployGovernanceContract(templateId, daoName);

        DAOInstance storage dao = daoInstances[daoId];
        dao.templateId = templateId;
        dao.daoGovernance = governanceAddress;
        dao.votingManager = address(votingManager);
        dao.treasury = treasury;
        dao.name = daoName;
        dao.description = daoDescription;
        dao.daoType = template.templateType;
        dao.founders = founders;
        dao.totalMembers = founders.length;
        dao.createdAt = block.timestamp;
        dao.isActive = true;

        // Add founders as admin members
        for (uint256 i = 0; i < founders.length; i++) {
            dao.isMember[founders[i]] = true;
            dao.membershipLevel[founders[i]] = 2; // Admin level
        }

        allDAOs.push(daoId);
        daosByCreator[msg.sender].push(daoId);
        
        // Update template usage
        template.usage++;

        emit DAOCreated(daoId, templateId, daoName, governanceAddress, msg.sender);
        emit TemplateUsageUpdated(templateId, template.usage);

        return daoId;
    }

    /**
     * @dev Get template by ID
     */
    function getTemplate(bytes32 templateId) 
        external 
        view 
        returns (GovernanceTemplate memory) 
    {
        return templates[templateId];
    }

    /**
     * @dev Get all templates by type
     */
    function getTemplatesByType(TemplateType templateType) 
        external 
        view 
        returns (bytes32[] memory) 
    {
        return templatesByType[templateType];
    }

    /**
     * @dev Get DAO details
     */
    function getDAO(bytes32 daoId) 
        external 
        view 
        returns (
            bytes32 templateId,
            address daoGovernance,
            address votingManager_,
            address treasury,
            string memory name,
            string memory description,
            TemplateType daoType,
            address[] memory founders,
            uint256 totalMembers,
            uint256 createdAt,
            bool isActive
        ) 
    {
        DAOInstance storage dao = daoInstances[daoId];
        return (
            dao.templateId,
            dao.daoGovernance,
            dao.votingManager,
            dao.treasury,
            dao.name,
            dao.description,
            dao.daoType,
            dao.founders,
            dao.totalMembers,
            dao.createdAt,
            dao.isActive
        );
    }

    /**
     * @dev Add member to DAO
     */
    function addDAOMember(
        bytes32 daoId,
        address member,
        uint256 level
    ) external {
        DAOInstance storage dao = daoInstances[daoId];
        require(dao.isActive, "DAO not active");
        require(
            dao.isMember[msg.sender] && dao.membershipLevel[msg.sender] >= 2,
            "Not authorized"
        );
        require(level <= 2, "Invalid membership level");

        if (!dao.isMember[member]) {
            dao.isMember[member] = true;
            dao.totalMembers++;
        }
        dao.membershipLevel[member] = level;

        emit DAOMemberAdded(daoId, member, level);
    }

    /**
     * @dev Remove member from DAO
     */
    function removeDAOMember(bytes32 daoId, address member) external {
        DAOInstance storage dao = daoInstances[daoId];
        require(dao.isActive, "DAO not active");
        require(
            dao.isMember[msg.sender] && dao.membershipLevel[msg.sender] >= 2,
            "Not authorized"
        );
        require(dao.isMember[member], "Not a member");

        dao.isMember[member] = false;
        dao.membershipLevel[member] = 0;
        dao.totalMembers--;

        emit DAOMemberRemoved(daoId, member);
    }

    /**
     * @dev Check if address is DAO member
     */
    function isDAOMember(bytes32 daoId, address account) 
        external 
        view 
        returns (bool, uint256) 
    {
        DAOInstance storage dao = daoInstances[daoId];
        return (dao.isMember[account], dao.membershipLevel[account]);
    }

    /**
     * @dev Get DAOs created by address
     */
    function getDAOsByCreator(address creator) 
        external 
        view 
        returns (bytes32[] memory) 
    {
        return daosByCreator[creator];
    }

    /**
     * @dev Get all active templates
     */
    function getAllActiveTemplates() 
        external 
        view 
        returns (bytes32[] memory activeTemplates) 
    {
        uint256 activeCount = 0;
        
        // Count active templates
        for (uint256 i = 0; i < allTemplates.length; i++) {
            if (templates[allTemplates[i]].isActive) {
                activeCount++;
            }
        }
        
        // Create active templates array
        activeTemplates = new bytes32[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allTemplates.length; i++) {
            if (templates[allTemplates[i]].isActive) {
                activeTemplates[index] = allTemplates[i];
                index++;
            }
        }
    }

    /**
     * @dev Get governance recommendations for template type
     */
    function getGovernanceRecommendations(TemplateType templateType)
        external
        pure
        returns (GovernanceParameters memory recommendations)
    {
        if (templateType == TemplateType.DEFI_PROTOCOL) {
            recommendations = GovernanceParameters({
                proposalThreshold: 1e18,     // 1 token
                votingDelay: 1,              // 1 block (~15 seconds)
                votingPeriod: 50400,         // ~1 week
                quorumNumerator: 400,        // 4%
                timelockDelay: 172800,       // 2 days
                vetoThreshold: 1000,         // 10%
                requiresSuperMajority: false
            });
        } else if (templateType == TemplateType.NFT_COMMUNITY) {
            recommendations = GovernanceParameters({
                proposalThreshold: 1e17,     // 0.1 token
                votingDelay: 7200,           // ~1 day
                votingPeriod: 100800,        // ~2 weeks
                quorumNumerator: 300,        // 3%
                timelockDelay: 86400,        // 1 day
                vetoThreshold: 1500,         // 15%
                requiresSuperMajority: false
            });
        } else if (templateType == TemplateType.CORPORATE_GOVERNANCE) {
            recommendations = GovernanceParameters({
                proposalThreshold: 1e19,     // 10 tokens
                votingDelay: 14400,          // ~2 days
                votingPeriod: 201600,        // ~1 month
                quorumNumerator: 1000,       // 10%
                timelockDelay: 604800,       // 1 week
                vetoThreshold: 2000,         // 20%
                requiresSuperMajority: true
            });
        } else { // HYBRID_DAO or CUSTOM
            recommendations = GovernanceParameters({
                proposalThreshold: 5e18,     // 5 tokens
                votingDelay: 7200,           // ~1 day
                votingPeriod: 100800,        // ~2 weeks
                quorumNumerator: 500,        // 5%
                timelockDelay: 259200,       // 3 days
                vetoThreshold: 1200,         // 12%
                requiresSuperMajority: false
            });
        }
    }

    /**
     * @dev Update template (admin only)
     */
    function updateTemplate(
        bytes32 templateId,
        GovernanceParameters memory parameters,
        BiometricRequirements memory biometricReqs,
        VotingConfiguration memory votingConfig
    ) external onlyRole(TEMPLATE_ADMIN_ROLE) {
        GovernanceTemplate storage template = templates[templateId];
        require(template.createdAt > 0, "Template not found");

        template.parameters = parameters;
        template.biometricReqs = biometricReqs;
        template.votingConfig = votingConfig;

        emit TemplateUpdated(templateId, msg.sender);
    }

    /**
     * @dev Deactivate template
     */
    function deactivateTemplate(bytes32 templateId) 
        external 
        onlyRole(TEMPLATE_ADMIN_ROLE) 
    {
        templates[templateId].isActive = false;
    }

    /**
     * @dev Get template usage statistics
     */
    function getTemplateStats() 
        external 
        view 
        returns (
            uint256 totalTemplates,
            uint256 activeTemplates,
            uint256 totalDAOs,
            uint256 activeDAOs
        ) 
    {
        totalTemplates = allTemplates.length;
        totalDAOs = allDAOs.length;
        
        for (uint256 i = 0; i < allTemplates.length; i++) {
            if (templates[allTemplates[i]].isActive) {
                activeTemplates++;
            }
        }
        
        for (uint256 i = 0; i < allDAOs.length; i++) {
            if (daoInstances[allDAOs[i]].isActive) {
                activeDAOs++;
            }
        }
    }

    // Internal functions

    /**
     * @dev Create default templates for common governance types
     */
    function _createDefaultTemplates() internal {
        // DeFi Protocol Template
        _createDefaultTemplate(
            TemplateType.DEFI_PROTOCOL,
            "DeFi Protocol Governance",
            "Standard governance template for DeFi protocols with parameter updates, treasury management, and protocol upgrades"
        );

        // NFT Community Template
        _createDefaultTemplate(
            TemplateType.NFT_COMMUNITY,
            "NFT Community Governance", 
            "Community-focused governance for NFT projects with creator rewards, roadmap decisions, and community initiatives"
        );

        // Corporate Governance Template
        _createDefaultTemplate(
            TemplateType.CORPORATE_GOVERNANCE,
            "Corporate Governance",
            "Enterprise-grade governance with board elections, shareholder proposals, and regulatory compliance"
        );
    }

    function _createDefaultTemplate(
        TemplateType templateType,
        string memory name,
        string memory description
    ) internal {
        GovernanceParameters memory params = this.getGovernanceRecommendations(templateType);
        
        BiometricRequirements memory biometricReqs = BiometricRequirements({
            mandatoryForProposals: true,
            mandatoryForVoting: false,
            minimumBiometricParticipation: 25, // 25%
            biometricWeightMultiplier: 110,    // 10% bonus
            allowsAnonymousVoting: true
        });

        VotingConfiguration memory votingConfig = VotingConfiguration({
            supportsBlindVoting: true,
            requiresZKProofs: true,
            maxVoteOptions: 10,
            allowsDelegation: true,
            allowsRevocation: false,
            participationReward: 0
        });

        bytes32 templateId = keccak256(abi.encodePacked(
            name,
            templateType,
            block.timestamp
        ));

        templates[templateId] = GovernanceTemplate({
            templateType: templateType,
            name: name,
            description: description,
            parameters: params,
            biometricReqs: biometricReqs,
            votingConfig: votingConfig,
            isActive: true,
            creator: address(this),
            createdAt: block.timestamp,
            usage: 0
        });

        allTemplates.push(templateId);
        templatesByType[templateType].push(templateId);
    }

    /**
     * @dev Deploy governance contract (simplified)
     */
    function _deployGovernanceContract(
        bytes32 templateId,
        string memory daoName
    ) internal returns (address) {
        // In production, deploy actual DAOGovernance contract with CREATE2
        // For now, return a deterministic address
        return address(uint160(uint256(keccak256(abi.encodePacked(
            templateId,
            daoName,
            block.timestamp
        )))));
    }
}