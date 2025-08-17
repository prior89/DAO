/**
 * Test Setup Configuration
 * Global test environment setup for biometric DAO voting system
 */

import { jest } from '@jest/globals';

// Mock crypto APIs for testing environment
global.crypto = {
  getRandomValues: jest.fn((arr: Uint8Array) => {
    for (let i = 0; i < arr.length; i++) {
      arr[i] = Math.floor(Math.random() * 256);
    }
    return arr;
  }),
  randomUUID: jest.fn(() => 'test-uuid-12345'),
  subtle: {
    digest: jest.fn(async (algorithm: string, data: BufferSource) => {
      // Mock SHA-256 hash
      return new ArrayBuffer(32);
    }),
    sign: jest.fn(async () => new ArrayBuffer(64)),
    verify: jest.fn(async () => true),
    generateKey: jest.fn(async () => ({} as CryptoKey)),
    importKey: jest.fn(async () => ({} as CryptoKey)),
    exportKey: jest.fn(async () => new ArrayBuffer(32))
  }
} as any;

// Mock performance API
global.performance = {
  now: jest.fn(() => Date.now())
} as any;

// Global test timeout
jest.setTimeout(30000);

// Console logging control
if (process.env.NODE_ENV === 'test') {
  global.console = {
    ...console,
    log: jest.fn(),
    debug: jest.fn(),
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn()
  };
}