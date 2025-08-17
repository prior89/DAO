/**
 * Hardware voting terminal interface definitions
 * Based on the biometric voting hardware specification
 */

export interface BiometricData {
  fingerprint: {
    features: FingerPrintFeature[];
    template: Uint8Array;
    quality: number;
  };
  hash: string;
  timestamp: number;
}

export interface FingerPrintFeature {
  type: 'minutiae' | 'ridge_ending' | 'bifurcation' | 'whorl' | 'arch';
  x: number;
  y: number;
  angle: number;
  quality: number;
}

export interface VotingSession {
  sessionId: string;
  voterId: string;
  biometricHash: string;
  timestamp: number;
  nonce: string;
  signature?: ECDSASignature;
}

export interface VoteData {
  sessionId: string;
  choice: string | number;
  timestamp: number;
  nonce: string;
  blindingFactor?: string;
}

export interface ECDSASignature {
  r: string;
  s: string;
  v?: number;
  publicKey: string;
}

export interface BlindSignature {
  blindedMessage: string;
  signature: ECDSASignature;
  blindingFactor: string;
}

export interface HardwareStatus {
  isConnected: boolean;
  batteryLevel?: number;
  securityStatus: 'secure' | 'warning' | 'breach';
  tamperDetected: boolean;
  lastHeartbeat: number;
}

export interface SecurityEvent {
  type: 'tamper_detection' | 'unauthorized_access' | 'voltage_anomaly' | 'frequency_anomaly' | 'em_attack';
  timestamp: number;
  severity: 'low' | 'medium' | 'high' | 'critical';
  details: Record<string, any>;
}

export interface EncryptedVotePacket {
  encryptedData: string;
  iv: string;
  authTag: string;
  signature: ECDSASignature;
  metadata: {
    version: string;
    algorithm: string;
    timestamp: number;
  };
}

export interface HardwareCommands {
  INIT_SESSION: 'INIT_SESSION';
  SCAN_BIOMETRIC: 'SCAN_BIOMETRIC';
  VERIFY_IDENTITY: 'VERIFY_IDENTITY';
  SUBMIT_VOTE: 'SUBMIT_VOTE';
  GENERATE_SIGNATURE: 'GENERATE_SIGNATURE';
  GET_STATUS: 'GET_STATUS';
  SECURE_ERASE: 'SECURE_ERASE';
  SHUTDOWN: 'SHUTDOWN';
}

export interface HardwareResponse<T = any> {
  success: boolean;
  data?: T;
  error?: {
    code: string;
    message: string;
    details?: any;
  };
  timestamp: number;
  signature: ECDSASignature;
}

export interface BLEConfiguration {
  serviceUUID: string;
  characteristicUUIDs: {
    command: string;
    response: string;
    status: string;
    security: string;
  };
  connectionTimeout: number;
  maxRetries: number;
  encryptionKey?: Uint8Array;
}

export interface ZeroKnowledgeProof {
  commitment: string;
  challenge: string;
  response: string;
  publicParameters: Record<string, string>;
}

export interface AnonymousToken {
  tokenId: string;
  issuedAt: number;
  expiresAt: number;
  scope: string[];
  nullifier: string;
  proof: ZeroKnowledgeProof;
}

export interface MixnetPacket {
  layerCount: number;
  encryptedLayers: string[];
  routingInfo: string;
  timestamp: number;
}

export const HARDWARE_COMMANDS: HardwareCommands = {
  INIT_SESSION: 'INIT_SESSION',
  SCAN_BIOMETRIC: 'SCAN_BIOMETRIC',
  VERIFY_IDENTITY: 'VERIFY_IDENTITY',
  SUBMIT_VOTE: 'SUBMIT_VOTE',
  GENERATE_SIGNATURE: 'GENERATE_SIGNATURE',
  GET_STATUS: 'GET_STATUS',
  SECURE_ERASE: 'SECURE_ERASE',
  SHUTDOWN: 'SHUTDOWN'
};

export const BLE_CONFIG: BLEConfiguration = {
  serviceUUID: '6E400001-B5A3-F393-E0A9-E50E24DCCA9E',
  characteristicUUIDs: {
    command: '6E400002-B5A3-F393-E0A9-E50E24DCCA9E',
    response: '6E400003-B5A3-F393-E0A9-E50E24DCCA9E',
    status: '6E400004-B5A3-F393-E0A9-E50E24DCCA9E',
    security: '6E400005-B5A3-F393-E0A9-E50E24DCCA9E'
  },
  connectionTimeout: 30000,
  maxRetries: 3
};