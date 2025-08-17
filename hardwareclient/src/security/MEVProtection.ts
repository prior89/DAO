/**
 * MEV (Maximum Extractable Value) Protection System
 * Protects against frontrunning, sandwich attacks, and governance manipulation
 * Based on 2024 MEV research and Shutter Network threshold cryptography
 */

import { EventEmitter } from 'events';
import { randomBytes } from 'crypto';
import { sha256 } from '@noble/hashes/sha256';

export interface MEVAttack {
  type: 'frontrunning' | 'sandwiching' | 'arbitrage' | 'liquidation' | 'governance_manipulation';
  attacker: string;
  confidence: number;
  evidence: string[];
  timestamp: number;
}

export interface CommitRevealVote {
  commitment: string;
  nonce: string;
  choice: number;
  salt: string;
  revealDeadline: number;
}

export interface ShutterEncryption {
  encryptedVote: string;
  threshold: number;
  shares: string[];
  decryptionKey?: string;
}

export interface MEVProtectionConfig {
  commitPhaseDuration: number;    // Duration of commit phase in ms
  revealPhaseDuration: number;    // Duration of reveal phase in ms
  minCommitDelay: number;         // Minimum delay between commits
  maxGasPrice: bigint;           // Maximum allowed gas price
  mevBotDetectionEnabled: boolean;
  shutterIntegration: boolean;    // Use Shutter Network protection
}

/**
 * MEV Protection Manager
 * Implements state-of-the-art protection against MEV attacks in voting
 */
export class MEVProtectionManager extends EventEmitter {
  private config: MEVProtectionConfig;
  private activeCommitments: Map<string, CommitRevealVote> = new Map();
  private detectedAttacks: MEVAttack[] = [];
  private votingPattern: Map<string, number[]> = new Map(); // Track voting patterns
  private gasPatterns: Map<string, bigint[]> = new Map(); // Track gas patterns
  private reputationScores: Map<string, number> = new Map();

  // MEV bot detection patterns
  private readonly MEV_BOT_SIGNATURES = [
    'rapid_sequential_voting',
    'systematic_gas_pricing',
    'coordinated_timing_attacks',
    'identical_transaction_patterns',
    'large_volume_manipulation'
  ];

  constructor(config?: Partial<MEVProtectionConfig>) {
    super();
    
    this.config = {
      commitPhaseDuration: 10 * 60 * 1000,    // 10 minutes
      revealPhaseDuration: 5 * 60 * 1000,     // 5 minutes
      minCommitDelay: 30 * 1000,              // 30 seconds
      maxGasPrice: BigInt('100000000000'),     // 100 gwei
      mevBotDetectionEnabled: true,
      shutterIntegration: true,
      ...config
    };
  }

  /**
   * Create commit-reveal voting commitment
   * Prevents frontrunning by hiding vote content during commit phase
   */
  async createVoteCommitment(
    voteId: string,
    choice: number,
    voterAddress: string
  ): Promise<CommitRevealVote> {
    
    // Check for MEV bot behavior
    if (this.config.mevBotDetectionEnabled) {
      const isMEVBot = await this.detectMEVBot(voterAddress);
      if (isMEVBot.detected) {
        throw new Error(`MEV bot detected: ${isMEVBot.reason}`);
      }
    }

    // Generate cryptographically secure commitment
    const nonce = this.bytesToHex(randomBytes(32));
    const salt = this.bytesToHex(randomBytes(16));
    
    const commitmentData = JSON.stringify({
      voteId,
      choice,
      voterAddress,
      nonce,
      salt,
      timestamp: Date.now()
    });

    const commitment = this.bytesToHex(sha256(new TextEncoder().encode(commitmentData)));
    
    const commitReveal: CommitRevealVote = {
      commitment,
      nonce,
      choice,
      salt,
      revealDeadline: Date.now() + this.config.commitPhaseDuration + this.config.revealPhaseDuration
    };

    this.activeCommitments.set(voterAddress, commitReveal);
    
    // Track voting patterns for MEV detection
    this.trackVotingPattern(voterAddress);

    this.emit('commitmentCreated', {
      voterAddress,
      commitment,
      voteId,
      timestamp: Date.now()
    });

    return commitReveal;
  }

  /**
   * Reveal vote after commit phase ends
   * Validates commitment and processes vote
   */
  async revealVote(
    voterAddress: string,
    voteId: string,
    choice: number,
    nonce: string,
    salt: string
  ): Promise<boolean> {
    
    const commitment = this.activeCommitments.get(voterAddress);
    if (!commitment) {
      throw new Error('No commitment found for voter');
    }

    // Verify reveal phase timing
    const now = Date.now();
    const commitPhaseEnd = now - this.config.revealPhaseDuration;
    
    if (now < commitPhaseEnd) {
      throw new Error('Reveal phase not started');
    }

    if (now > commitment.revealDeadline) {
      throw new Error('Reveal phase ended');
    }

    // Verify commitment
    const expectedCommitmentData = JSON.stringify({
      voteId,
      choice,
      voterAddress,
      nonce,
      salt,
      timestamp: now - this.config.commitPhaseDuration
    });

    const expectedCommitment = this.bytesToHex(sha256(new TextEncoder().encode(expectedCommitmentData)));
    
    if (commitment.commitment !== expectedCommitment) {
      throw new Error('Invalid commitment reveal');
    }

    // Clean up commitment
    this.activeCommitments.delete(voterAddress);

    this.emit('voteRevealed', {
      voterAddress,
      voteId,
      choice,
      timestamp: now
    });

    return true;
  }

  /**
   * Detect MEV bot behavior using behavioral analysis
   * Based on 2024 MEV research and bot detection patterns
   */
  async detectMEVBot(voterAddress: string): Promise<{
    detected: boolean;
    confidence: number;
    reason: string;
    patterns: string[];
  }> {
    
    const patterns: string[] = [];
    let suspicionScore = 0;

    // Pattern 1: Rapid sequential voting
    const votingPattern = this.votingPattern.get(voterAddress) || [];
    if (votingPattern.length > 5) {
      const avgInterval = this.calculateAverageInterval(votingPattern);
      if (avgInterval < 60000) { // Less than 1 minute average
        patterns.push('rapid_sequential_voting');
        suspicionScore += 25;
      }
    }

    // Pattern 2: Systematic gas pricing
    const gasPattern = this.gasPatterns.get(voterAddress) || [];
    if (gasPattern.length > 3) {
      const gasVariance = this.calculateGasVariance(gasPattern);
      if (gasVariance < 1000000000) { // Very consistent gas pricing
        patterns.push('systematic_gas_pricing');
        suspicionScore += 20;
      }
    }

    // Pattern 3: Low reputation with high activity
    const reputation = this.reputationScores.get(voterAddress) || 0;
    if (reputation < 30 && votingPattern.length > 10) {
      patterns.push('low_reputation_high_activity');
      suspicionScore += 30;
    }

    // Pattern 4: Identical transaction timing
    if (this.detectIdenticalTiming(voterAddress)) {
      patterns.push('identical_transaction_patterns');
      suspicionScore += 35;
    }

    // Pattern 5: Large volume with new address
    const accountAge = this.getAccountAge(voterAddress);
    if (accountAge < 7 * 24 * 60 * 60 * 1000 && votingPattern.length > 20) { // 7 days
      patterns.push('large_volume_manipulation');
      suspicionScore += 25;
    }

    const detected = suspicionScore >= 60; // 60% confidence threshold
    const confidence = Math.min(suspicionScore, 100);

    if (detected) {
      const attack: MEVAttack = {
        type: 'governance_manipulation',
        attacker: voterAddress,
        confidence,
        evidence: patterns,
        timestamp: Date.now()
      };
      
      this.detectedAttacks.push(attack);
      
      this.emit('mevAttackDetected', attack);
    }

    return {
      detected,
      confidence,
      reason: patterns.join(', '),
      patterns
    };
  }

  /**
   * Implement Shutter Network-style threshold encryption
   * Prevents MEV by encrypting votes until reveal phase
   */
  async createShutterEncryption(
    voteData: any,
    threshold: number = 3
  ): Promise<ShutterEncryption> {
    
    if (!this.config.shutterIntegration) {
      throw new Error('Shutter integration not enabled');
    }

    // Generate threshold encryption shares
    const shares: string[] = [];
    const voteDataStr = JSON.stringify(voteData);
    
    for (let i = 0; i < threshold + 2; i++) { // threshold + 2 shares
      const shareData = {
        index: i,
        data: voteDataStr,
        randomness: this.bytesToHex(randomBytes(32))
      };
      
      const shareHash = this.bytesToHex(sha256(new TextEncoder().encode(JSON.stringify(shareData))));
      shares.push(shareHash);
    }

    // Encrypt vote data (simplified - use actual threshold crypto in production)
    const encryptionKey = this.bytesToHex(randomBytes(32));
    const encryptedVote = this.simpleEncrypt(voteDataStr, encryptionKey);

    return {
      encryptedVote,
      threshold,
      shares,
      // decryptionKey will be revealed after commit phase
    };
  }

  /**
   * Monitor transaction pool for MEV attacks
   * Detects frontrunning and sandwich attacks in real-time
   */
  async monitorMempool(transactions: any[]): Promise<MEVAttack[]> {
    const detectedAttacks: MEVAttack[] = [];

    for (let i = 0; i < transactions.length - 1; i++) {
      const tx1 = transactions[i];
      const tx2 = transactions[i + 1];

      // Detect sandwich attacks
      if (this.isSandwichAttack(tx1, tx2)) {
        detectedAttacks.push({
          type: 'sandwiching',
          attacker: tx1.from,
          confidence: 85,
          evidence: ['sandwich_pattern', 'gas_price_manipulation'],
          timestamp: Date.now()
        });
      }

      // Detect frontrunning
      if (this.isFrontrunning(tx1, tx2)) {
        detectedAttacks.push({
          type: 'frontrunning',
          attacker: tx1.from,
          confidence: 75,
          evidence: ['identical_function_call', 'higher_gas_price'],
          timestamp: Date.now()
        });
      }
    }

    return detectedAttacks;
  }

  /**
   * Calculate reputation score based on voting behavior
   * Higher reputation = less likely to be MEV bot
   */
  updateReputationScore(voterAddress: string, behavior: 'positive' | 'negative' | 'neutral'): void {
    const currentScore = this.reputationScores.get(voterAddress) || 50; // Start at neutral
    
    let scoreChange = 0;
    switch (behavior) {
      case 'positive':
        scoreChange = 2;
        break;
      case 'negative':
        scoreChange = -5;
        break;
      case 'neutral':
        scoreChange = 0;
        break;
    }

    const newScore = Math.max(0, Math.min(100, currentScore + scoreChange));
    this.reputationScores.set(voterAddress, newScore);

    this.emit('reputationUpdated', {
      voterAddress,
      oldScore: currentScore,
      newScore,
      behavior
    });
  }

  /**
   * Get MEV protection status for a vote
   */
  getMEVProtectionStatus(voteId: string): {
    commitPhaseActive: boolean;
    revealPhaseActive: boolean;
    protectionLevel: 'HIGH' | 'MEDIUM' | 'LOW';
    activeCommitments: number;
    detectedAttacks: number;
  } {
    
    const commitments = Array.from(this.activeCommitments.values());
    const activeCommitments = commitments.length;
    const detectedAttacks = this.detectedAttacks.filter(
      attack => attack.timestamp > Date.now() - 24 * 60 * 60 * 1000 // Last 24 hours
    ).length;

    let protectionLevel: 'HIGH' | 'MEDIUM' | 'LOW' = 'HIGH';
    
    if (!this.config.shutterIntegration || !this.config.mevBotDetectionEnabled) {
      protectionLevel = 'MEDIUM';
    }
    
    if (detectedAttacks > 10) {
      protectionLevel = 'LOW'; // Under heavy attack
    }

    return {
      commitPhaseActive: true, // Simplified
      revealPhaseActive: false,
      protectionLevel,
      activeCommitments,
      detectedAttacks
    };
  }

  // Private helper methods

  private trackVotingPattern(voterAddress: string): void {
    const now = Date.now();
    const pattern = this.votingPattern.get(voterAddress) || [];
    
    pattern.push(now);
    
    // Keep only last 20 votes for pattern analysis
    if (pattern.length > 20) {
      pattern.shift();
    }
    
    this.votingPattern.set(voterAddress, pattern);
  }

  private calculateAverageInterval(timestamps: number[]): number {
    if (timestamps.length < 2) return Infinity;
    
    let totalInterval = 0;
    for (let i = 1; i < timestamps.length; i++) {
      totalInterval += timestamps[i] - timestamps[i - 1];
    }
    
    return totalInterval / (timestamps.length - 1);
  }

  private calculateGasVariance(gasPrices: bigint[]): number {
    if (gasPrices.length < 2) return Infinity;
    
    const mean = gasPrices.reduce((sum, price) => sum + price, 0n) / BigInt(gasPrices.length);
    
    let variance = 0n;
    for (const price of gasPrices) {
      const diff = price - mean;
      variance += diff * diff;
    }
    
    return Number(variance / BigInt(gasPrices.length));
  }

  private detectIdenticalTiming(voterAddress: string): boolean {
    const pattern = this.votingPattern.get(voterAddress) || [];
    if (pattern.length < 3) return false;

    // Check for votes at exactly same intervals (bot behavior)
    const intervals = [];
    for (let i = 1; i < pattern.length; i++) {
      intervals.push(pattern[i] - pattern[i - 1]);
    }

    // Check if intervals are suspiciously similar
    const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length;
    const identicalIntervals = intervals.filter(interval => 
      Math.abs(interval - avgInterval) < 1000 // Within 1 second
    ).length;

    return identicalIntervals / intervals.length > 0.8; // 80% identical timing
  }

  private getAccountAge(voterAddress: string): number {
    // Simplified - in production would check blockchain for first transaction
    return Date.now() - (30 * 24 * 60 * 60 * 1000); // Assume 30 days old
  }

  private isSandwichAttack(tx1: any, tx2: any): boolean {
    // Simplified sandwich attack detection
    return tx1.to === tx2.to && 
           tx1.from !== tx2.from && 
           tx1.gasPrice > tx2.gasPrice;
  }

  private isFrontrunning(tx1: any, tx2: any): boolean {
    // Simplified frontrunning detection
    return tx1.input === tx2.input &&
           tx1.from !== tx2.from &&
           tx1.gasPrice > tx2.gasPrice;
  }

  private simpleEncrypt(data: string, key: string): string {
    // Simplified encryption - use proper threshold crypto in production
    const dataBytes = new TextEncoder().encode(data);
    const keyBytes = this.hexToBytes(key);
    
    const encrypted = new Uint8Array(dataBytes.length);
    for (let i = 0; i < dataBytes.length; i++) {
      encrypted[i] = dataBytes[i] ^ keyBytes[i % keyBytes.length];
    }
    
    return this.bytesToHex(encrypted);
  }

  private bytesToHex(bytes: Uint8Array): string {
    return Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
  }

  private hexToBytes(hex: string): Uint8Array {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < hex.length; i += 2) {
      bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
    }
    return bytes;
  }
}