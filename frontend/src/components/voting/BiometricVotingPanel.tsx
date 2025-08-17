/**
 * Biometric Voting Panel Component
 * Handles hardware terminal connection and biometric authentication
 * Based on 2024 voting system security standards
 */

'use client';

import React, { useState, useEffect, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  ShieldCheckIcon, 
  FingerprintIcon, 
  WifiIcon,
  LockClosedIcon,
  ExclamationTriangleIcon,
  CheckCircleIcon,
  XCircleIcon
} from '@heroicons/react/24/outline';
import { toast } from 'react-hot-toast';
import { useWebSocket } from '../../hooks/useWebSocket';
import { useBiometricAuth } from '../../hooks/useBiometricAuth';
import { useHardwareConnection } from '../../hooks/useHardwareConnection';

export interface BiometricVotingPanelProps {
  voteId: string;
  onVoteSubmitted: (result: VoteResult) => void;
  onError: (error: string) => void;
  votingOptions: VotingOption[];
  requiresBiometric: boolean;
  allowsBlindVoting: boolean;
}

export interface VotingOption {
  id: string;
  title: string;
  description?: string;
}

export interface VoteResult {
  voteId: string;
  choice: string;
  nullifier: string;
  signature: string;
  isBlind: boolean;
  timestamp: number;
}

type VotingState = 
  | 'disconnected'
  | 'connecting'
  | 'connected'
  | 'authenticating'
  | 'authenticated'
  | 'voting'
  | 'submitting'
  | 'completed'
  | 'error';

export default function BiometricVotingPanel({
  voteId,
  onVoteSubmitted,
  onError,
  votingOptions,
  requiresBiometric,
  allowsBlindVoting
}: BiometricVotingPanelProps) {
  const [votingState, setVotingState] = useState<VotingState>('disconnected');
  const [selectedOption, setSelectedOption] = useState<string>('');
  const [biometricData, setBiometricData] = useState<any>(null);
  const [hardwareStatus, setHardwareStatus] = useState<any>(null);
  const [errorMessage, setErrorMessage] = useState<string>('');
  const [useBlindVoting, setUseBlindVoting] = useState(false);

  const { socket, isConnected } = useWebSocket();
  const { authenticate, isAuthenticated, authError } = useBiometricAuth();
  const { 
    connect, 
    disconnect, 
    submitVote, 
    getStatus,
    isConnected: hardwareConnected,
    connectionError 
  } = useHardwareConnection();

  // Handle hardware connection
  const handleConnect = useCallback(async () => {
    try {
      setVotingState('connecting');
      await connect();
      setVotingState('connected');
      
      const status = await getStatus();
      setHardwareStatus(status);
      
      toast.success('Hardware terminal connected successfully');
    } catch (error) {
      setVotingState('error');
      setErrorMessage('Failed to connect to hardware terminal');
      onError('Hardware connection failed');
    }
  }, [connect, getStatus, onError]);

  // Handle biometric authentication
  const handleBiometricAuth = useCallback(async () => {
    if (!requiresBiometric) {
      setVotingState('authenticated');
      return;
    }

    try {
      setVotingState('authenticating');
      const authResult = await authenticate(voteId);
      setBiometricData(authResult);
      setVotingState('authenticated');
      
      toast.success('Biometric authentication successful');
    } catch (error) {
      setVotingState('error');
      setErrorMessage('Biometric authentication failed');
      onError('Authentication failed');
    }
  }, [authenticate, requiresBiometric, voteId, onError]);

  // Handle vote submission
  const handleSubmitVote = useCallback(async () => {
    if (!selectedOption) {
      toast.error('Please select a voting option');
      return;
    }

    try {
      setVotingState('submitting');
      
      const voteResult = await submitVote({
        voteId,
        choice: selectedOption,
        biometricData,
        useBlindVoting
      });

      setVotingState('completed');
      onVoteSubmitted(voteResult);
      
      toast.success('Vote submitted successfully!');
    } catch (error) {
      setVotingState('error');
      setErrorMessage('Vote submission failed');
      onError('Vote submission failed');
    }
  }, [selectedOption, voteId, biometricData, useBlindVoting, submitVote, onVoteSubmitted, onError]);

  // Auto-progress through states
  useEffect(() => {
    if (votingState === 'connected' && requiresBiometric) {
      const timer = setTimeout(() => {
        handleBiometricAuth();
      }, 1000);
      return () => clearTimeout(timer);
    }
  }, [votingState, requiresBiometric, handleBiometricAuth]);

  // Render voting state indicator
  const renderStateIndicator = () => {
    const states = [
      { key: 'disconnected', label: 'Connect Hardware', icon: WifiIcon, color: 'gray' },
      { key: 'connecting', label: 'Connecting...', icon: WifiIcon, color: 'yellow' },
      { key: 'connected', label: 'Connected', icon: CheckCircleIcon, color: 'green' },
      { key: 'authenticating', label: 'Authenticating...', icon: FingerprintIcon, color: 'blue' },
      { key: 'authenticated', label: 'Authenticated', icon: ShieldCheckIcon, color: 'green' },
      { key: 'voting', label: 'Voting', icon: LockClosedIcon, color: 'blue' },
      { key: 'submitting', label: 'Submitting...', icon: LockClosedIcon, color: 'yellow' },
      { key: 'completed', label: 'Completed', icon: CheckCircleIcon, color: 'green' },
      { key: 'error', label: 'Error', icon: XCircleIcon, color: 'red' }
    ];

    return (
      <div className="flex items-center space-x-4 mb-6">
        {states.map((state, index) => {
          const isActive = state.key === votingState;
          const isPassed = states.findIndex(s => s.key === votingState) > index;
          const Icon = state.icon;
          
          return (
            <div key={state.key} className="flex items-center">
              <div className={`
                w-10 h-10 rounded-full flex items-center justify-center border-2
                ${isActive ? `border-${state.color}-500 bg-${state.color}-100` : ''}
                ${isPassed ? `border-green-500 bg-green-100` : ''}
                ${!isActive && !isPassed ? 'border-gray-300 bg-gray-50' : ''}
              `}>
                <Icon className={`w-5 h-5 ${
                  isActive ? `text-${state.color}-600` : 
                  isPassed ? 'text-green-600' : 
                  'text-gray-400'
                }`} />
              </div>
              {index < states.length - 1 && (
                <div className={`w-8 h-0.5 ${
                  isPassed ? 'bg-green-500' : 'bg-gray-300'
                }`} />
              )}
            </div>
          );
        })}
      </div>
    );
  };

  // Render voting options
  const renderVotingOptions = () => {
    if (votingState !== 'authenticated' && votingState !== 'voting') {
      return null;
    }

    return (
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="space-y-4"
      >
        <h3 className="text-lg font-semibold text-gray-900 mb-4">
          Select Your Vote
        </h3>
        
        {votingOptions.map((option) => (
          <motion.button
            key={option.id}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            onClick={() => {
              setSelectedOption(option.id);
              setVotingState('voting');
            }}
            className={`
              w-full p-4 text-left border-2 rounded-lg transition-all
              ${selectedOption === option.id 
                ? 'border-blue-500 bg-blue-50' 
                : 'border-gray-200 hover:border-gray-300'
              }
            `}
          >
            <div className="flex items-center justify-between">
              <div>
                <h4 className="font-medium text-gray-900">{option.title}</h4>
                {option.description && (
                  <p className="text-sm text-gray-600 mt-1">{option.description}</p>
                )}
              </div>
              <div className={`
                w-5 h-5 rounded-full border-2
                ${selectedOption === option.id 
                  ? 'border-blue-500 bg-blue-500' 
                  : 'border-gray-300'
                }
              `}>
                {selectedOption === option.id && (
                  <CheckCircleIcon className="w-full h-full text-white" />
                )}
              </div>
            </div>
          </motion.button>
        ))}

        {allowsBlindVoting && (
          <div className="mt-6 p-4 bg-gray-50 rounded-lg">
            <label className="flex items-center space-x-3">
              <input
                type="checkbox"
                checked={useBlindVoting}
                onChange={(e) => setUseBlindVoting(e.target.checked)}
                className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
              />
              <div>
                <span className="text-sm font-medium text-gray-900">
                  Use anonymous voting
                </span>
                <p className="text-xs text-gray-600 mt-1">
                  Your vote will be encrypted and completely anonymous
                </p>
              </div>
            </label>
          </div>
        )}
      </motion.div>
    );
  };

  // Render hardware status
  const renderHardwareStatus = () => {
    if (!hardwareStatus) return null;

    return (
      <div className="bg-gray-50 rounded-lg p-4 mb-6">
        <h4 className="text-sm font-medium text-gray-900 mb-2">Hardware Status</h4>
        <div className="grid grid-cols-2 gap-4 text-sm">
          <div>
            <span className="text-gray-600">Security Status:</span>
            <span className={`ml-2 font-medium ${
              hardwareStatus.securityStatus === 'secure' ? 'text-green-600' : 'text-red-600'
            }`}>
              {hardwareStatus.securityStatus}
            </span>
          </div>
          <div>
            <span className="text-gray-600">Battery:</span>
            <span className="ml-2 font-medium text-gray-900">
              {hardwareStatus.batteryLevel}%
            </span>
          </div>
          <div>
            <span className="text-gray-600">Tamper Detection:</span>
            <span className={`ml-2 font-medium ${
              hardwareStatus.tamperDetected ? 'text-red-600' : 'text-green-600'
            }`}>
              {hardwareStatus.tamperDetected ? 'Alert' : 'Normal'}
            </span>
          </div>
          <div>
            <span className="text-gray-600">Last Heartbeat:</span>
            <span className="ml-2 font-medium text-gray-900">
              {new Date(hardwareStatus.lastHeartbeat).toLocaleTimeString()}
            </span>
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className="max-w-2xl mx-auto p-6 bg-white rounded-lg shadow-lg">
      <div className="text-center mb-8">
        <FingerprintIcon className="w-16 h-16 text-blue-600 mx-auto mb-4" />
        <h2 className="text-2xl font-bold text-gray-900 mb-2">
          Biometric Voting Terminal
        </h2>
        <p className="text-gray-600">
          Secure, privacy-preserving voting with hardware authentication
        </p>
      </div>

      {renderStateIndicator()}
      {renderHardwareStatus()}

      <AnimatePresence mode="wait">
        {votingState === 'disconnected' && (
          <motion.div
            key="connect"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="text-center"
          >
            <p className="text-gray-600 mb-6">
              Connect to your biometric voting terminal to begin
            </p>
            <button
              onClick={handleConnect}
              className="px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
            >
              Connect Hardware Terminal
            </button>
          </motion.div>
        )}

        {votingState === 'connecting' && (
          <motion.div
            key="connecting"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="text-center"
          >
            <div className="animate-spin w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full mx-auto mb-4" />
            <p className="text-gray-600">Connecting to hardware terminal...</p>
          </motion.div>
        )}

        {votingState === 'authenticating' && (
          <motion.div
            key="authenticating"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="text-center"
          >
            <FingerprintIcon className="w-16 h-16 text-blue-600 mx-auto mb-4 animate-pulse" />
            <p className="text-gray-600">Please place your finger on the sensor</p>
          </motion.div>
        )}

        {(votingState === 'authenticated' || votingState === 'voting') && renderVotingOptions()}

        {votingState === 'voting' && selectedOption && (
          <motion.div
            key="submit"
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="mt-6 text-center"
          >
            <p className="text-gray-600 mb-4">
              Ready to submit your vote for: 
              <strong className="text-gray-900 ml-1">
                {votingOptions.find(opt => opt.id === selectedOption)?.title}
              </strong>
            </p>
            <button
              onClick={handleSubmitVote}
              className="px-8 py-3 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
            >
              Submit Vote
            </button>
          </motion.div>
        )}

        {votingState === 'submitting' && (
          <motion.div
            key="submitting"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="text-center"
          >
            <div className="animate-spin w-8 h-8 border-4 border-green-600 border-t-transparent rounded-full mx-auto mb-4" />
            <p className="text-gray-600">Submitting your vote to blockchain...</p>
          </motion.div>
        )}

        {votingState === 'completed' && (
          <motion.div
            key="completed"
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            className="text-center"
          >
            <CheckCircleIcon className="w-16 h-16 text-green-600 mx-auto mb-4" />
            <h3 className="text-xl font-semibold text-gray-900 mb-2">
              Vote Submitted Successfully!
            </h3>
            <p className="text-gray-600">
              Your vote has been securely recorded on the blockchain
            </p>
          </motion.div>
        )}

        {votingState === 'error' && (
          <motion.div
            key="error"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="text-center"
          >
            <ExclamationTriangleIcon className="w-16 h-16 text-red-600 mx-auto mb-4" />
            <h3 className="text-xl font-semibold text-gray-900 mb-2">
              Error Occurred
            </h3>
            <p className="text-red-600 mb-4">{errorMessage}</p>
            <button
              onClick={() => {
                setVotingState('disconnected');
                setErrorMessage('');
              }}
              className="px-6 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors"
            >
              Try Again
            </button>
          </motion.div>
        )}
      </AnimatePresence>

      {connectionError && (
        <div className="mt-4 p-4 bg-red-50 border border-red-200 rounded-lg">
          <p className="text-red-600 text-sm">{connectionError}</p>
        </div>
      )}
    </div>
  );
}