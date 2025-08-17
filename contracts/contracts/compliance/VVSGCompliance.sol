// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../voting/VotingManager.sol";

/**
 * @title VVSGCompliance
 * @dev Implements EAC VVSG 2.0 compliance requirements for electronic voting systems
 * Ensures adherence to U.S. Election Assistance Commission standards
 * Effective November 16, 2023 - all new certifications must meet VVSG 2.0
 */
contract VVSGCompliance is AccessControl, ReentrancyGuard, Pausable {
    
    bytes32 public constant ELECTION_OFFICIAL_ROLE = keccak256("ELECTION_OFFICIAL_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");
    bytes32 public constant SECURITY_OFFICER_ROLE = keccak256("SECURITY_OFFICER_ROLE");

    enum SecurityLevel {
        DEVELOPMENT,    // For testing only
        CERTIFIED,      // EAC certified
        PRODUCTION      // Live election use
    }

    enum AuditRequirement {
        SOFTWARE_INDEPENDENCE,      // VVSG 2.0 Requirement 1
        VOTER_VERIFICATION,         // VVSG 2.0 Requirement 2  
        BALLOT_SECRECY,            // VVSG 2.0 Requirement 3
        ACCESS_CONTROL,            // VVSG 2.0 Requirement 4
        PHYSICAL_SECURITY,         // VVSG 2.0 Requirement 5
        CRYPTOGRAPHIC_PROTECTION,  // VVSG 2.0 Requirement 6
        SYSTEM_INTEGRITY,          // VVSG 2.0 Requirement 7
        DETECTION_PROTECTION       // VVSG 2.0 Requirement 8
    }

    struct VVSGCertification {
        string certificationId;
        address votingSystem;
        SecurityLevel securityLevel;
        uint256 certificationDate;
        uint256 expirationDate;
        string vstlName;           // Voting System Test Laboratory
        bool isActive;
        mapping(AuditRequirement => bool) requirementsMet;
        string[] securityPatches;
        uint256 lastSecurityUpdate;
    }

    struct SecurityPatch {
        string patchId;
        string description;
        uint256 releaseDate;
        address[] affectedSystems;
        bool isCritical;
        string mitigation;
    }

    struct PenetrationTestResult {
        string testId;
        address testLab;
        uint256 testDate;
        uint256 vulnerabilitiesFound;
        uint256 criticalIssues;
        uint256 highIssues;
        uint256 mediumIssues;
        uint256 lowIssues;
        bool passed;
        string report;
    }

    struct AccessibilityCompliance {
        bool supportsVOVAT;        // Voter Over-Votes Alerts and Tabulation
        bool supportsAudio;        // Audio ballot interface
        bool supportsLargeFont;    // Large font display
        bool supportsHighContrast; // High contrast display
        bool supportsHeadphones;   // Private audio voting
        bool supportsLanguage;     // Multi-language support
        uint256 wcagLevel;         // WCAG 2.1 compliance level (AA = 2)
    }

    // Storage
    mapping(bytes32 => VVSGCertification) public certifications;
    mapping(string => SecurityPatch) public securityPatches;
    mapping(bytes32 => PenetrationTestResult[]) public penetrationTests;
    mapping(address => AccessibilityCompliance) public accessibilityCompliance;
    mapping(address => bool) public accreditedVSTL;
    
    bytes32[] public certifiedSystems;
    string[] public availablePatches;
    
    VotingManager public immutable votingManager;

    // Events
    event SystemCertified(
        bytes32 indexed certificationId,
        address indexed votingSystem,
        SecurityLevel securityLevel,
        string vstlName
    );
    
    event SecurityPatchReleased(
        string indexed patchId,
        address[] affectedSystems,
        bool isCritical
    );
    
    event PenetrationTestCompleted(
        bytes32 indexed systemId,
        address testLab,
        uint256 vulnerabilities,
        bool passed
    );
    
    event VVSGRequirementUpdated(
        bytes32 indexed certificationId,
        AuditRequirement requirement,
        bool status
    );

    event AccessibilityComplianceUpdated(
        address indexed system,
        uint256 wcagLevel
    );

    // Custom errors
    error SystemNotCertified();
    error CertificationExpired();
    error UnauthorizedVSTL();
    error SecurityPatchRequired();
    error PenetrationTestFailed();
    error AccessibilityNonCompliant();

    constructor(address _votingManager) {
        votingManager = VotingManager(_votingManager);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ELECTION_OFFICIAL_ROLE, msg.sender);
        
        // Initialize default VVSG 2.0 requirements
        _setupVVSGRequirements();
    }

    /**
     * @dev Certify voting system to VVSG 2.0 standards
     * @param votingSystem Address of voting system contract
     * @param vstlName Accredited Voting System Test Laboratory
     * @param certificationData VVSG 2.0 compliance data
     */
    function certifyVotingSystem(
        address votingSystem,
        string memory vstlName,
        bool[] memory requirementsMet,
        AccessibilityCompliance memory accessibility
    ) external onlyRole(ELECTION_OFFICIAL_ROLE) returns (bytes32) {
        
        require(accreditedVSTL[msg.sender], "Only accredited VSTL can certify");
        require(requirementsMet.length == 8, "Must check all 8 VVSG requirements");

        bytes32 certificationId = keccak256(abi.encodePacked(
            votingSystem,
            vstlName,
            block.timestamp
        ));

        VVSGCertification storage cert = certifications[certificationId];
        cert.certificationId = string(abi.encodePacked("VVSG-", certificationId));
        cert.votingSystem = votingSystem;
        cert.securityLevel = SecurityLevel.CERTIFIED;
        cert.certificationDate = block.timestamp;
        cert.expirationDate = block.timestamp + (5 * 365 * 24 * 60 * 60); // 5 years
        cert.vstlName = vstlName;
        cert.isActive = true;
        cert.lastSecurityUpdate = block.timestamp;

        // Set VVSG 2.0 requirements compliance
        AuditRequirement[] memory requirements = _getVVSGRequirements();
        for (uint256 i = 0; i < requirements.length && i < requirementsMet.length; i++) {
            cert.requirementsMet[requirements[i]] = requirementsMet[i];
        }

        // Verify all critical requirements are met
        require(
            cert.requirementsMet[AuditRequirement.SOFTWARE_INDEPENDENCE] &&
            cert.requirementsMet[AuditRequirement.VOTER_VERIFICATION] &&
            cert.requirementsMet[AuditRequirement.BALLOT_SECRECY],
            "Critical VVSG requirements not met"
        );

        // Set accessibility compliance
        accessibilityCompliance[votingSystem] = accessibility;
        require(accessibility.wcagLevel >= 2, "Must meet WCAG 2.1 AA standards");

        certifiedSystems.push(certificationId);

        emit SystemCertified(certificationId, votingSystem, SecurityLevel.CERTIFIED, vstlName);
        emit AccessibilityComplianceUpdated(votingSystem, accessibility.wcagLevel);

        return certificationId;
    }

    /**
     * @dev Conduct mandatory penetration testing (VVSG 2.0 requirement)
     * @param systemId Certified system identifier
     * @param testLab Accredited security testing laboratory
     */
    function conductPenetrationTest(
        bytes32 systemId,
        address testLab,
        uint256 vulnerabilitiesFound,
        uint256[] memory severityCounts, // [critical, high, medium, low]
        string memory reportHash
    ) external onlyRole(SECURITY_OFFICER_ROLE) {
        
        VVSGCertification storage cert = certifications[systemId];
        require(cert.isActive, "System not certified");
        require(accreditedVSTL[testLab], "Test lab not accredited");

        bool testPassed = vulnerabilitiesFound == 0 || 
                         (severityCounts[0] == 0 && severityCounts[1] <= 2); // Max 2 high severity

        PenetrationTestResult memory testResult = PenetrationTestResult({
            testId: string(abi.encodePacked("PENTEST-", block.timestamp)),
            testLab: testLab,
            testDate: block.timestamp,
            vulnerabilitiesFound: vulnerabilitiesFound,
            criticalIssues: severityCounts[0],
            highIssues: severityCounts[1],
            mediumIssues: severityCounts[2],
            lowIssues: severityCounts[3],
            passed: testPassed,
            report: reportHash
        });

        penetrationTests[systemId].push(testResult);

        if (!testPassed) {
            cert.isActive = false; // Suspend certification until issues resolved
        }

        emit PenetrationTestCompleted(systemId, testLab, vulnerabilitiesFound, testPassed);
    }

    /**
     * @dev Release security patch for certified systems
     * @param patchId Unique patch identifier
     * @param description Patch description
     * @param affectedSystems Systems requiring this patch
     * @param isCritical Whether patch addresses critical vulnerability
     */
    function releaseSecurityPatch(
        string memory patchId,
        string memory description,
        address[] memory affectedSystems,
        bool isCritical,
        string memory mitigation
    ) external onlyRole(SECURITY_OFFICER_ROLE) {
        
        SecurityPatch storage patch = securityPatches[patchId];
        patch.patchId = patchId;
        patch.description = description;
        patch.releaseDate = block.timestamp;
        patch.affectedSystems = affectedSystems;
        patch.isCritical = isCritical;
        patch.mitigation = mitigation;

        availablePatches.push(patchId);

        // Update security patch records for affected systems
        for (uint256 i = 0; i < affectedSystems.length; i++) {
            bytes32[] memory systemCerts = _getSystemCertifications(affectedSystems[i]);
            for (uint256 j = 0; j < systemCerts.length; j++) {
                certifications[systemCerts[j]].securityPatches.push(patchId);
                certifications[systemCerts[j]].lastSecurityUpdate = block.timestamp;
            }
        }

        emit SecurityPatchReleased(patchId, affectedSystems, isCritical);
    }

    /**
     * @dev Verify VVSG 2.0 compliance for voting operation
     * @param systemAddress Voting system to verify
     * @param operation Specific operation to verify
     */
    function verifyVVSGCompliance(
        address systemAddress,
        string memory operation
    ) external view returns (bool compliant, string memory reason) {
        
        bytes32[] memory systemCerts = _getSystemCertifications(systemAddress);
        if (systemCerts.length == 0) {
            return (false, "System not certified to VVSG 2.0");
        }

        VVSGCertification storage cert = certifications[systemCerts[0]];
        
        // Check certification is active and not expired
        if (!cert.isActive) {
            return (false, "Certification suspended");
        }
        
        if (block.timestamp > cert.expirationDate) {
            return (false, "Certification expired");
        }

        // Check operation-specific requirements
        if (keccak256(abi.encodePacked(operation)) == keccak256("VOTE_CASTING")) {
            if (!cert.requirementsMet[AuditRequirement.VOTER_VERIFICATION]) {
                return (false, "Voter verification requirement not met");
            }
            if (!cert.requirementsMet[AuditRequirement.BALLOT_SECRECY]) {
                return (false, "Ballot secrecy requirement not met");
            }
        }

        if (keccak256(abi.encodePacked(operation)) == keccak256("VOTE_TALLYING")) {
            if (!cert.requirementsMet[AuditRequirement.SOFTWARE_INDEPENDENCE]) {
                return (false, "Software independence requirement not met");
            }
            if (!cert.requirementsMet[AuditRequirement.SYSTEM_INTEGRITY]) {
                return (false, "System integrity requirement not met");
            }
        }

        return (true, "VVSG 2.0 compliant");
    }

    /**
     * @dev Update VVSG requirement status
     * @param certificationId System certification ID
     * @param requirement VVSG requirement to update
     * @param status New compliance status
     */
    function updateVVSGRequirement(
        bytes32 certificationId,
        AuditRequirement requirement,
        bool status
    ) external onlyRole(AUDITOR_ROLE) {
        
        VVSGCertification storage cert = certifications[certificationId];
        require(cert.isActive, "Certification not active");
        
        cert.requirementsMet[requirement] = status;
        
        emit VVSGRequirementUpdated(certificationId, requirement, status);
    }

    /**
     * @dev Get certification details
     * @param certificationId Certification identifier
     */
    function getCertificationDetails(bytes32 certificationId)
        external
        view
        returns (
            string memory certId,
            address votingSystem,
            SecurityLevel securityLevel,
            uint256 certificationDate,
            uint256 expirationDate,
            string memory vstlName,
            bool isActive,
            uint256 lastSecurityUpdate
        )
    {
        VVSGCertification storage cert = certifications[certificationId];
        return (
            cert.certificationId,
            cert.votingSystem,
            cert.securityLevel,
            cert.certificationDate,
            cert.expirationDate,
            cert.vstlName,
            cert.isActive,
            cert.lastSecurityUpdate
        );
    }

    /**
     * @dev Check if all VVSG 2.0 requirements are met
     * @param certificationId Certification to check
     */
    function areAllRequirementsMet(bytes32 certificationId) 
        external 
        view 
        returns (bool allMet, AuditRequirement[] memory unmetRequirements) 
    {
        VVSGCertification storage cert = certifications[certificationId];
        AuditRequirement[] memory requirements = _getVVSGRequirements();
        
        AuditRequirement[] memory unmet = new AuditRequirement[](8);
        uint256 unmetCount = 0;
        
        allMet = true;
        for (uint256 i = 0; i < requirements.length; i++) {
            if (!cert.requirementsMet[requirements[i]]) {
                allMet = false;
                unmet[unmetCount] = requirements[i];
                unmetCount++;
            }
        }
        
        // Resize array to actual unmet count
        unmetRequirements = new AuditRequirement[](unmetCount);
        for (uint256 i = 0; i < unmetCount; i++) {
            unmetRequirements[i] = unmet[i];
        }
    }

    /**
     * @dev Get penetration test history
     * @param systemId System certification ID
     */
    function getPenetrationTestHistory(bytes32 systemId)
        external
        view
        returns (PenetrationTestResult[] memory tests)
    {
        return penetrationTests[systemId];
    }

    /**
     * @dev Emergency certification suspension
     * @param certificationId Certification to suspend
     * @param reason Suspension reason
     */
    function emergencySuspendCertification(
        bytes32 certificationId,
        string memory reason
    ) external onlyRole(SECURITY_OFFICER_ROLE) {
        
        VVSGCertification storage cert = certifications[certificationId];
        cert.isActive = false;
        
        // Pause associated voting system
        _pauseVotingSystem(cert.votingSystem);
        
        emit VVSGRequirementUpdated(certificationId, AuditRequirement.SYSTEM_INTEGRITY, false);
    }

    /**
     * @dev Accredit Voting System Test Laboratory
     * @param vstlAddress VSTL contract address
     * @param accredited Whether to accredit or revoke
     */
    function accreditVSTL(address vstlAddress, bool accredited) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        accreditedVSTL[vstlAddress] = accredited;
    }

    /**
     * @dev Check if system requires security updates
     * @param systemAddress Voting system address
     */
    function requiresSecurityUpdate(address systemAddress) 
        external 
        view 
        returns (bool required, string[] memory requiredPatches) 
    {
        bytes32[] memory systemCerts = _getSystemCertifications(systemAddress);
        if (systemCerts.length == 0) {
            return (false, new string[](0));
        }

        VVSGCertification storage cert = certifications[systemCerts[0]];
        string[] memory missing = new string[](availablePatches.length);
        uint256 missingCount = 0;

        for (uint256 i = 0; i < availablePatches.length; i++) {
            string memory patchId = availablePatches[i];
            bool hasApplied = false;
            
            for (uint256 j = 0; j < cert.securityPatches.length; j++) {
                if (keccak256(abi.encodePacked(cert.securityPatches[j])) == 
                    keccak256(abi.encodePacked(patchId))) {
                    hasApplied = true;
                    break;
                }
            }
            
            if (!hasApplied && securityPatches[patchId].isCritical) {
                missing[missingCount] = patchId;
                missingCount++;
            }
        }

        required = missingCount > 0;
        requiredPatches = new string[](missingCount);
        for (uint256 i = 0; i < missingCount; i++) {
            requiredPatches[i] = missing[i];
        }
    }

    // Internal functions

    /**
     * @dev Setup default VVSG 2.0 requirements
     */
    function _setupVVSGRequirements() internal {
        // VVSG 2.0 requirements are initialized in contract state
        // Implementation would set up the 8 core requirements
    }

    /**
     * @dev Get all VVSG 2.0 requirements
     */
    function _getVVSGRequirements() internal pure returns (AuditRequirement[] memory) {
        AuditRequirement[] memory requirements = new AuditRequirement[](8);
        requirements[0] = AuditRequirement.SOFTWARE_INDEPENDENCE;
        requirements[1] = AuditRequirement.VOTER_VERIFICATION;
        requirements[2] = AuditRequirement.BALLOT_SECRECY;
        requirements[3] = AuditRequirement.ACCESS_CONTROL;
        requirements[4] = AuditRequirement.PHYSICAL_SECURITY;
        requirements[5] = AuditRequirement.CRYPTOGRAPHIC_PROTECTION;
        requirements[6] = AuditRequirement.SYSTEM_INTEGRITY;
        requirements[7] = AuditRequirement.DETECTION_PROTECTION;
        return requirements;
    }

    /**
     * @dev Get certifications for a voting system
     */
    function _getSystemCertifications(address systemAddress) 
        internal 
        view 
        returns (bytes32[] memory systemCerts) 
    {
        uint256 count = 0;
        
        // Count matching certifications
        for (uint256 i = 0; i < certifiedSystems.length; i++) {
            if (certifications[certifiedSystems[i]].votingSystem == systemAddress) {
                count++;
            }
        }
        
        // Build array of matching certifications
        systemCerts = new bytes32[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < certifiedSystems.length; i++) {
            if (certifications[certifiedSystems[i]].votingSystem == systemAddress) {
                systemCerts[index] = certifiedSystems[i];
                index++;
            }
        }
    }

    /**
     * @dev Pause voting system (emergency response)
     */
    function _pauseVotingSystem(address systemAddress) internal {
        // In production, call pause function on voting system
        // For now, just log the action
    }
}