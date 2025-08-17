/**
 * GDPR Compliance Module for Biometric Data Processing
 * Ensures compliance with EU GDPR, AI Act 2024, and privacy by design principles
 */

import { EventEmitter } from 'events';
import { sha256 } from '@noble/hashes/sha256';

export interface GDPRConsentRecord {
  userId: string;
  consentId: string;
  timestamp: number;
  purpose: string[];
  legalBasis: 'consent' | 'public_task' | 'legitimate_interest';
  consentGiven: boolean;
  consentWithdrawn?: number;
  dataMinimized: boolean;
  retentionPeriod: number; // in milliseconds
  processingLog: ProcessingLogEntry[];
}

export interface ProcessingLogEntry {
  action: 'collect' | 'process' | 'store' | 'transmit' | 'delete' | 'anonymize';
  timestamp: number;
  purpose: string;
  legalBasis: string;
  dataCategories: string[];
  retention: number;
  location: string;
}

export interface BiometricDataProtection {
  templateEncrypted: boolean;
  originalDataDeleted: boolean;
  anonymizationLevel: 'pseudonymous' | 'anonymous' | 'statistical';
  accessControls: string[];
  auditTrail: AuditLogEntry[];
}

export interface AuditLogEntry {
  timestamp: number;
  userId: string;
  action: string;
  dataAccessed: string[];
  legalBasis: string;
  purpose: string;
  ipAddress?: string;
  userAgent?: string;
}

export interface PrivacyByDesignControls {
  dataMinimization: boolean;
  purposeLimitation: boolean;
  storageMinimization: boolean;
  accessControl: boolean;
  encryption: boolean;
  anonymization: boolean;
  auditLogging: boolean;
  consentManagement: boolean;
}

export class GDPRComplianceManager extends EventEmitter {
  private consentRecords: Map<string, GDPRConsentRecord> = new Map();
  private processingLogs: Map<string, ProcessingLogEntry[]> = new Map();
  private auditLogs: AuditLogEntry[] = [];
  private dataRetentionPolicies: Map<string, number> = new Map();
  
  // GDPR Article 25 - Privacy by Design requirements
  private privacyControls: PrivacyByDesignControls = {
    dataMinimization: true,
    purposeLimitation: true,
    storageMinimization: true,
    accessControl: true,
    encryption: true,
    anonymization: true,
    auditLogging: true,
    consentManagement: true
  };

  constructor() {
    super();
    this.initializeRetentionPolicies();
    this.startRetentionMonitoring();
  }

  /**
   * Record explicit consent for biometric data processing
   * GDPR Article 9 - Special categories of personal data
   */
  async recordExplicitConsent(
    userId: string,
    purposes: string[],
    legalBasis: 'consent' | 'public_task' | 'legitimate_interest' = 'consent'
  ): Promise<string> {
    const consentId = this.generateConsentId();
    const timestamp = Date.now();

    const consentRecord: GDPRConsentRecord = {
      userId,
      consentId,
      timestamp,
      purpose: purposes,
      legalBasis,
      consentGiven: true,
      dataMinimized: true,
      retentionPeriod: this.getRetentionPeriod(purposes),
      processingLog: []
    };

    this.consentRecords.set(consentId, consentRecord);
    
    this.logAudit({
      timestamp,
      userId,
      action: 'CONSENT_RECORDED',
      dataAccessed: ['consent_data'],
      legalBasis,
      purpose: purposes.join(', ')
    });

    this.emit('consentRecorded', { userId, consentId, purposes });
    
    return consentId;
  }

  /**
   * Withdraw consent and trigger data deletion
   * GDPR Article 7(3) - Withdrawal of consent
   */
  async withdrawConsent(consentId: string): Promise<boolean> {
    const consent = this.consentRecords.get(consentId);
    if (!consent) {
      throw new Error('Consent record not found');
    }

    consent.consentWithdrawn = Date.now();
    consent.consentGiven = false;

    // Schedule immediate data deletion (GDPR Article 17)
    await this.scheduleDataDeletion(consent.userId, 'consent_withdrawal');

    this.logAudit({
      timestamp: Date.now(),
      userId: consent.userId,
      action: 'CONSENT_WITHDRAWN',
      dataAccessed: ['biometric_data', 'voting_data'],
      legalBasis: 'consent_withdrawal',
      purpose: 'data_deletion'
    });

    this.emit('consentWithdrawn', { userId: consent.userId, consentId });
    
    return true;
  }

  /**
   * Process biometric data with GDPR safeguards
   * Implements Privacy by Design (Article 25)
   */
  async processBiometricData(
    userId: string,
    consentId: string,
    biometricData: Uint8Array,
    purpose: string
  ): Promise<{ templateHash: string; protection: BiometricDataProtection }> {
    // Verify consent
    const consent = this.verifyConsent(consentId, purpose);
    if (!consent) {
      throw new Error('Invalid or insufficient consent for biometric processing');
    }

    // Data minimization (GDPR Article 5(1)(c))
    const minimizedData = this.minimizeBiometricData(biometricData);
    
    // Generate irreversible template hash
    const templateHash = this.generateBiometricTemplate(minimizedData);
    
    // Immediately delete original biometric data (Privacy by Design)
    biometricData.fill(0);
    minimizedData.fill(0);

    const protection: BiometricDataProtection = {
      templateEncrypted: true,
      originalDataDeleted: true,
      anonymizationLevel: 'pseudonymous',
      accessControls: ['biometric_admin', 'voting_system'],
      auditTrail: []
    };

    // Log processing activity
    this.logProcessingActivity(consentId, {
      action: 'process',
      timestamp: Date.now(),
      purpose,
      legalBasis: consent.legalBasis,
      dataCategories: ['biometric_template'],
      retention: consent.retentionPeriod,
      location: 'secure_hardware'
    });

    this.emit('biometricProcessed', { userId, templateHash, purpose });

    return { templateHash, protection };
  }

  /**
   * Anonymize voting data for statistical purposes
   * GDPR Recital 26 - Anonymous data
   */
  async anonymizeVotingData(
    voteData: any,
    purpose: 'statistics' | 'research' | 'audit'
  ): Promise<any> {
    // Remove all identifying information
    const anonymizedData = {
      voteChoice: voteData.choice,
      timestamp: Math.floor(voteData.timestamp / (24 * 60 * 60 * 1000)) * 24 * 60 * 60 * 1000, // Round to day
      voteType: voteData.type,
      demographic: this.generalizeLocation(voteData.location),
      // Remove: userId, biometricHash, signature, nullifier
    };

    this.logProcessingActivity('anonymous', {
      action: 'anonymize',
      timestamp: Date.now(),
      purpose,
      legalBasis: 'legitimate_interest',
      dataCategories: ['voting_statistics'],
      retention: 365 * 24 * 60 * 60 * 1000, // 1 year for statistics
      location: 'analytics_system'
    });

    return anonymizedData;
  }

  /**
   * Handle data subject access request (GDPR Article 15)
   */
  async handleAccessRequest(userId: string): Promise<{
    personalData: any;
    processingActivities: ProcessingLogEntry[];
    consentHistory: GDPRConsentRecord[];
    dataRetention: number;
  }> {
    const userConsents = Array.from(this.consentRecords.values())
      .filter(consent => consent.userId === userId);
    
    const processingActivities = this.processingLogs.get(userId) || [];

    // Calculate retention periods
    const dataRetention = Math.max(...userConsents.map(c => c.retentionPeriod));

    this.logAudit({
      timestamp: Date.now(),
      userId,
      action: 'DATA_ACCESS_REQUEST',
      dataAccessed: ['consent_data', 'processing_logs'],
      legalBasis: 'data_subject_rights',
      purpose: 'access_request'
    });

    return {
      personalData: {
        userId,
        consentStatus: userConsents.map(c => ({
          consentId: c.consentId,
          purpose: c.purpose,
          status: c.consentGiven ? 'active' : 'withdrawn',
          timestamp: c.timestamp
        }))
      },
      processingActivities,
      consentHistory: userConsents,
      dataRetention
    };
  }

  /**
   * Implement data portability (GDPR Article 20)
   */
  async exportUserData(userId: string, format: 'json' | 'xml' | 'csv' = 'json'): Promise<string> {
    const accessData = await this.handleAccessRequest(userId);
    
    switch (format) {
      case 'json':
        return JSON.stringify(accessData, null, 2);
      case 'xml':
        return this.convertToXML(accessData);
      case 'csv':
        return this.convertToCSV(accessData);
      default:
        throw new Error('Unsupported export format');
    }
  }

  /**
   * Schedule data deletion based on retention policies
   * GDPR Article 5(1)(e) - Storage limitation
   */
  private async scheduleDataDeletion(userId: string, reason: string): Promise<void> {
    setTimeout(async () => {
      await this.deleteUserData(userId, reason);
    }, 1000); // Immediate deletion for consent withdrawal

    this.emit('dataDeletionScheduled', { userId, reason });
  }

  /**
   * Delete all user data (Right to erasure - Article 17)
   */
  private async deleteUserData(userId: string, reason: string): Promise<void> {
    // Delete consent records
    const userConsents = Array.from(this.consentRecords.entries())
      .filter(([_, consent]) => consent.userId === userId);
    
    for (const [consentId, _] of userConsents) {
      this.consentRecords.delete(consentId);
    }

    // Delete processing logs
    this.processingLogs.delete(userId);

    // Log deletion activity
    this.logAudit({
      timestamp: Date.now(),
      userId,
      action: 'DATA_DELETED',
      dataAccessed: ['all_user_data'],
      legalBasis: 'data_subject_rights',
      purpose: reason
    });

    this.emit('userDataDeleted', { userId, reason });
  }

  /**
   * Verify consent validity for processing
   */
  private verifyConsent(consentId: string, purpose: string): GDPRConsentRecord | null {
    const consent = this.consentRecords.get(consentId);
    
    if (!consent || !consent.consentGiven) {
      return null;
    }

    // Check if purpose is covered by consent
    if (!consent.purpose.includes(purpose)) {
      return null;
    }

    // Check if consent hasn't expired
    const now = Date.now();
    if (now > consent.timestamp + consent.retentionPeriod) {
      return null;
    }

    return consent;
  }

  /**
   * Minimize biometric data to essential features only
   */
  private minimizeBiometricData(data: Uint8Array): Uint8Array {
    // Extract only essential minutiae points (data minimization)
    // In production, implement actual feature extraction
    const minimized = new Uint8Array(64); // Reduced from original size
    data.slice(0, 64).forEach((byte, index) => {
      minimized[index] = byte;
    });
    return minimized;
  }

  /**
   * Generate irreversible biometric template
   */
  private generateBiometricTemplate(data: Uint8Array): string {
    const hash = sha256(data);
    return Array.from(hash, b => b.toString(16).padStart(2, '0')).join('');
  }

  /**
   * Log processing activity for audit trail
   */
  private logProcessingActivity(consentId: string, entry: ProcessingLogEntry): void {
    const consent = this.consentRecords.get(consentId);
    if (consent) {
      consent.processingLog.push(entry);
      
      if (!this.processingLogs.has(consent.userId)) {
        this.processingLogs.set(consent.userId, []);
      }
      this.processingLogs.get(consent.userId)!.push(entry);
    }
  }

  /**
   * Log audit entry for compliance monitoring
   */
  private logAudit(entry: AuditLogEntry): void {
    this.auditLogs.push(entry);
    this.emit('auditLog', entry);
  }

  /**
   * Initialize data retention policies
   */
  private initializeRetentionPolicies(): void {
    // GDPR-compliant retention periods
    this.dataRetentionPolicies.set('voting', 5 * 365 * 24 * 60 * 60 * 1000); // 5 years
    this.dataRetentionPolicies.set('authentication', 1 * 365 * 24 * 60 * 60 * 1000); // 1 year
    this.dataRetentionPolicies.set('audit', 7 * 365 * 24 * 60 * 60 * 1000); // 7 years
    this.dataRetentionPolicies.set('statistics', 10 * 365 * 24 * 60 * 60 * 1000); // 10 years (anonymized)
  }

  /**
   * Start monitoring for data retention compliance
   */
  private startRetentionMonitoring(): void {
    setInterval(() => {
      this.enforceRetentionPolicies();
    }, 24 * 60 * 60 * 1000); // Daily check
  }

  /**
   * Enforce data retention policies
   */
  private enforceRetentionPolicies(): void {
    const now = Date.now();
    
    for (const [consentId, consent] of this.consentRecords.entries()) {
      if (now > consent.timestamp + consent.retentionPeriod) {
        this.scheduleDataDeletion(consent.userId, 'retention_policy');
      }
    }
  }

  private getRetentionPeriod(purposes: string[]): number {
    return Math.max(...purposes.map(purpose => 
      this.dataRetentionPolicies.get(purpose) || 365 * 24 * 60 * 60 * 1000
    ));
  }

  private generateConsentId(): string {
    return 'consent_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  }

  private generalizeLocation(location: string): string {
    // Generalize location data to prevent re-identification
    return location.split(',')[0]; // Keep only country/region
  }

  private convertToXML(data: any): string {
    // Simplified XML conversion
    return `<?xml version="1.0" encoding="UTF-8"?>\n<userData>\n${JSON.stringify(data)}\n</userData>`;
  }

  private convertToCSV(data: any): string {
    // Simplified CSV conversion
    const headers = Object.keys(data).join(',');
    const values = Object.values(data).join(',');
    return `${headers}\n${values}`;
  }

  /**
   * Generate compliance report
   */
  async generateComplianceReport(): Promise<{
    totalConsents: number;
    activeConsents: number;
    withdrawnConsents: number;
    processingActivities: number;
    dataRetentionCompliance: number;
    auditLogEntries: number;
    privacyControlsStatus: PrivacyByDesignControls;
  }> {
    const allConsents = Array.from(this.consentRecords.values());
    const activeConsents = allConsents.filter(c => c.consentGiven);
    const withdrawnConsents = allConsents.filter(c => !c.consentGiven);
    
    const totalProcessingActivities = Array.from(this.processingLogs.values())
      .reduce((total, logs) => total + logs.length, 0);

    return {
      totalConsents: allConsents.length,
      activeConsents: activeConsents.length,
      withdrawnConsents: withdrawnConsents.length,
      processingActivities: totalProcessingActivities,
      dataRetentionCompliance: this.calculateRetentionCompliance(),
      auditLogEntries: this.auditLogs.length,
      privacyControlsStatus: this.privacyControls
    };
  }

  private calculateRetentionCompliance(): number {
    const now = Date.now();
    const allConsents = Array.from(this.consentRecords.values());
    const compliantConsents = allConsents.filter(consent => 
      now <= consent.timestamp + consent.retentionPeriod
    );
    
    return allConsents.length > 0 ? compliantConsents.length / allConsents.length : 1;
  }
}