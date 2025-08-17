/**
 * Hardware Client Main Entry Point
 * Biometric DAO Voting System - Hardware Communication Module
 */

export { BLEConnectionManager, BLEDevice } from './ble/connection';
export { ECDSACrypto } from './crypto/ecdsa';
export { VotingProtocol, VotingOptions, VoteChoice, VotingResult } from './protocols/voting';

export {
  BiometricData,
  FingerPrintFeature,
  VotingSession,
  VoteData,
  ECDSASignature,
  BlindSignature,
  HardwareStatus,
  SecurityEvent,
  EncryptedVotePacket,
  HardwareResponse,
  BLEConfiguration,
  ZeroKnowledgeProof,
  AnonymousToken,
  MixnetPacket,
  HARDWARE_COMMANDS,
  BLE_CONFIG
} from './types/hardware';

// Main hardware client class for easy integration
export class HardwareVotingClient {
  private bleManager: BLEConnectionManager;
  private votingProtocol: VotingProtocol;

  constructor(config?: Partial<BLEConfiguration>) {
    this.bleManager = new BLEConnectionManager(config);
    this.votingProtocol = new VotingProtocol(this.bleManager);
  }

  /**
   * Get BLE connection manager
   */
  getBLEManager(): BLEConnectionManager {
    return this.bleManager;
  }

  /**
   * Get voting protocol handler
   */
  getVotingProtocol(): VotingProtocol {
    return this.votingProtocol;
  }

  /**
   * Initialize and connect to hardware device
   */
  async initialize(deviceId?: string): Promise<boolean> {
    try {
      // Scan for devices if no specific device ID provided
      if (!deviceId) {
        const devices = await this.bleManager.scanDevices();
        if (devices.length === 0) {
          throw new Error('No hardware voting devices found');
        }
        deviceId = devices[0].id;
      }

      // Connect to device
      const connected = await this.bleManager.connect(deviceId);
      if (!connected) {
        throw new Error('Failed to connect to hardware device');
      }

      console.log('Hardware voting client initialized successfully');
      return true;
    } catch (error) {
      console.error('Hardware client initialization failed:', error);
      throw error;
    }
  }

  /**
   * Cleanup and disconnect
   */
  async cleanup(): Promise<void> {
    try {
      await this.votingProtocol.endVotingSession();
      await this.bleManager.disconnect();
      console.log('Hardware voting client cleaned up');
    } catch (error) {
      console.error('Cleanup failed:', error);
      throw error;
    }
  }
}

// Export default instance for convenience
export default HardwareVotingClient;