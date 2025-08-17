/**
 * WebSocket Server for Real-time Voting Updates
 * Based on 2024 Mexican Federal Election real-time tallying pattern
 */

import { Server as SocketIOServer } from 'socket.io';
import { Server as HttpServer } from 'http';
import { Socket } from 'socket.io';
import { Logger } from '../utils/Logger';
import { BlockchainSyncService } from '../services/BlockchainSync';
import jwt from 'jsonwebtoken';

export interface WebSocketConfig {
  cors: {
    origin: string[];
    credentials: boolean;
  };
  jwt: {
    secret: string;
    expiresIn: string;
  };
}

export interface ClientConnection {
  id: string;
  userId?: string;
  subscribedVotes: Set<string>;
  isAuthenticated: boolean;
  connectedAt: number;
  lastActivity: number;
}

export interface VoteUpdateMessage {
  type: 'VOTE_CAST' | 'TALLY_UPDATE' | 'VOTE_FINALIZED' | 'ENCRYPTION_UPDATE';
  voteId: string;
  data: any;
  timestamp: number;
}

export class VotingWebSocketServer {
  private io: SocketIOServer;
  private logger: Logger;
  private blockchainSync: BlockchainSyncService;
  private connections: Map<string, ClientConnection> = new Map();
  private rooms: Map<string, Set<string>> = new Map(); // voteId -> Set of socket IDs
  private config: WebSocketConfig;

  constructor(
    httpServer: HttpServer,
    blockchainSync: BlockchainSyncService,
    config: WebSocketConfig
  ) {
    this.logger = new Logger('VotingWebSocket');
    this.blockchainSync = blockchainSync;
    this.config = config;

    this.io = new SocketIOServer(httpServer, {
      cors: config.cors,
      transports: ['websocket', 'polling'],
      pingTimeout: 60000,
      pingInterval: 25000
    });

    this.setupMiddleware();
    this.setupEventHandlers();
    this.setupBlockchainListeners();
  }

  /**
   * Setup authentication and rate limiting middleware
   */
  private setupMiddleware(): void {
    // Authentication middleware
    this.io.use(async (socket, next) => {
      try {
        const token = socket.handshake.auth.token;
        
        if (!token) {
          return next(new Error('Authentication token required'));
        }

        const decoded = jwt.verify(token, this.config.jwt.secret) as any;
        socket.data.user = decoded;
        socket.data.userId = decoded.id;
        
        this.logger.info(`User authenticated: ${decoded.id}`);
        next();
      } catch (error) {
        this.logger.security({
          type: 'AUTHENTICATION_FAILURE',
          severity: 'MEDIUM',
          details: { 
            socketId: socket.id,
            error: error instanceof Error ? error.message : 'Unknown error'
          },
          timestamp: Date.now(),
          source: 'WebSocket'
        });
        next(new Error('Authentication failed'));
      }
    });

    // Rate limiting middleware
    this.io.use(this.rateLimitMiddleware.bind(this));
  }

  /**
   * Rate limiting middleware to prevent spam
   */
  private rateLimitMiddleware(socket: Socket, next: (err?: Error) => void): void {
    const connection = this.connections.get(socket.id);
    
    if (connection) {
      const now = Date.now();
      const timeSinceLastActivity = now - connection.lastActivity;
      
      // Allow max 10 requests per second
      if (timeSinceLastActivity < 100) {
        return next(new Error('Rate limit exceeded'));
      }
      
      connection.lastActivity = now;
    }
    
    next();
  }

  /**
   * Setup WebSocket event handlers
   */
  private setupEventHandlers(): void {
    this.io.on('connection', (socket: Socket) => {
      this.handleConnection(socket);

      socket.on('subscribe_vote', (data) => this.handleSubscribeVote(socket, data));
      socket.on('unsubscribe_vote', (data) => this.handleUnsubscribeVote(socket, data));
      socket.on('get_vote_status', (data) => this.handleGetVoteStatus(socket, data));
      socket.on('get_realtime_tally', (data) => this.handleGetRealtimeTally(socket, data));
      socket.on('ping', () => this.handlePing(socket));
      
      socket.on('disconnect', () => this.handleDisconnection(socket));
      socket.on('error', (error) => this.handleError(socket, error));
    });
  }

  /**
   * Handle new client connection
   */
  private handleConnection(socket: Socket): void {
    const connection: ClientConnection = {
      id: socket.id,
      userId: socket.data.userId,
      subscribedVotes: new Set(),
      isAuthenticated: true,
      connectedAt: Date.now(),
      lastActivity: Date.now()
    };

    this.connections.set(socket.id, connection);
    
    this.logger.info(`Client connected: ${socket.id}, User: ${socket.data.userId}`);
    
    // Send welcome message with server status
    socket.emit('connected', {
      socketId: socket.id,
      serverTime: Date.now(),
      supportedEvents: [
        'subscribe_vote',
        'unsubscribe_vote', 
        'get_vote_status',
        'get_realtime_tally'
      ]
    });

    this.logger.audit('WEBSOCKET_CONNECT', socket.data.userId, {
      socketId: socket.id,
      timestamp: Date.now()
    });
  }

  /**
   * Handle vote subscription
   */
  private async handleSubscribeVote(socket: Socket, data: { voteId: string }): Promise<void> {
    try {
      const { voteId } = data;
      const connection = this.connections.get(socket.id);
      
      if (!connection) {
        return;
      }

      // Add to user's subscriptions
      connection.subscribedVotes.add(voteId);
      
      // Add to vote room
      if (!this.rooms.has(voteId)) {
        this.rooms.set(voteId, new Set());
      }
      this.rooms.get(voteId)!.add(socket.id);
      
      // Join Socket.IO room
      socket.join(`vote_${voteId}`);
      
      // Start monitoring this vote on blockchain
      await this.blockchainSync.monitorVoteProgress(voteId);
      
      // Send current vote status
      const voteStatus = await this.getVoteStatus(voteId);
      socket.emit('vote_subscribed', {
        voteId,
        status: voteStatus,
        timestamp: Date.now()
      });

      this.logger.info(`Client ${socket.id} subscribed to vote: ${voteId}`);
      
      this.logger.audit('VOTE_SUBSCRIBE', socket.data.userId, {
        voteId,
        socketId: socket.id
      });
    } catch (error) {
      this.logger.error('Failed to subscribe to vote:', error);
      socket.emit('error', {
        type: 'SUBSCRIPTION_ERROR',
        message: 'Failed to subscribe to vote',
        voteId: data.voteId
      });
    }
  }

  /**
   * Handle vote unsubscription
   */
  private handleUnsubscribeVote(socket: Socket, data: { voteId: string }): void {
    const { voteId } = data;
    const connection = this.connections.get(socket.id);
    
    if (!connection) {
      return;
    }

    // Remove from user's subscriptions
    connection.subscribedVotes.delete(voteId);
    
    // Remove from vote room
    const room = this.rooms.get(voteId);
    if (room) {
      room.delete(socket.id);
      if (room.size === 0) {
        this.rooms.delete(voteId);
      }
    }
    
    // Leave Socket.IO room
    socket.leave(`vote_${voteId}`);
    
    socket.emit('vote_unsubscribed', {
      voteId,
      timestamp: Date.now()
    });

    this.logger.info(`Client ${socket.id} unsubscribed from vote: ${voteId}`);
  }

  /**
   * Handle vote status request
   */
  private async handleGetVoteStatus(socket: Socket, data: { voteId: string }): Promise<void> {
    try {
      const voteStatus = await this.getVoteStatus(data.voteId);
      
      socket.emit('vote_status', {
        voteId: data.voteId,
        status: voteStatus,
        timestamp: Date.now()
      });
    } catch (error) {
      this.logger.error('Failed to get vote status:', error);
      socket.emit('error', {
        type: 'STATUS_ERROR',
        message: 'Failed to get vote status',
        voteId: data.voteId
      });
    }
  }

  /**
   * Handle real-time tally request
   */
  private async handleGetRealtimeTally(socket: Socket, data: { voteId: string }): Promise<void> {
    try {
      const tally = await this.blockchainSync.getEncryptedTally(data.voteId);
      
      socket.emit('realtime_tally', {
        voteId: data.voteId,
        tally: {
          totalVotes: tally.totalVotes,
          lastUpdated: tally.lastUpdated,
          isEncrypted: true // Don't expose vote breakdown until decryption
        },
        timestamp: Date.now()
      });
    } catch (error) {
      this.logger.error('Failed to get real-time tally:', error);
      socket.emit('error', {
        type: 'TALLY_ERROR',
        message: 'Failed to get real-time tally',
        voteId: data.voteId
      });
    }
  }

  /**
   * Handle ping for connection health check
   */
  private handlePing(socket: Socket): void {
    const connection = this.connections.get(socket.id);
    if (connection) {
      connection.lastActivity = Date.now();
    }
    
    socket.emit('pong', { timestamp: Date.now() });
  }

  /**
   * Handle client disconnection
   */
  private handleDisconnection(socket: Socket): void {
    const connection = this.connections.get(socket.id);
    
    if (connection) {
      // Remove from all vote rooms
      for (const voteId of connection.subscribedVotes) {
        const room = this.rooms.get(voteId);
        if (room) {
          room.delete(socket.id);
          if (room.size === 0) {
            this.rooms.delete(voteId);
          }
        }
      }
      
      this.connections.delete(socket.id);
      
      this.logger.info(`Client disconnected: ${socket.id}`);
      this.logger.audit('WEBSOCKET_DISCONNECT', socket.data?.userId || 'unknown', {
        socketId: socket.id,
        connectedDuration: Date.now() - connection.connectedAt
      });
    }
  }

  /**
   * Handle WebSocket errors
   */
  private handleError(socket: Socket, error: Error): void {
    this.logger.error(`WebSocket error for ${socket.id}:`, error);
    
    this.logger.security({
      type: 'ENCRYPTION_ERROR',
      severity: 'MEDIUM',
      details: {
        socketId: socket.id,
        error: error.message,
        userId: socket.data?.userId
      },
      timestamp: Date.now(),
      source: 'WebSocket'
    });
  }

  /**
   * Setup blockchain event listeners for real-time updates
   */
  private setupBlockchainListeners(): void {
    // Real-time vote detection
    this.blockchainSync.on('voteDetected', (data) => {
      this.broadcastToVoteRoom(data.voteId, {
        type: 'VOTE_CAST',
        voteId: data.voteId,
        data: {
          nullifier: data.nullifier,
          timestamp: data.timestamp,
          isBlind: data.isBlind,
          blockNumber: data.blockNumber
        },
        timestamp: Date.now()
      });
    });

    // Real-time tally updates (like Mexican Federal Election)
    this.blockchainSync.on('realTimeTallyUpdate', (data) => {
      this.broadcastToVoteRoom(data.voteId, {
        type: 'TALLY_UPDATE',
        voteId: data.voteId,
        data: {
          totalVotes: data.totalVotes,
          isEncrypted: true,
          blockNumber: data.blockNumber
        },
        timestamp: Date.now()
      });
    });

    // Vote finalization
    this.blockchainSync.on('voteFinalized', (data) => {
      this.broadcastToVoteRoom(data.voteId, {
        type: 'VOTE_FINALIZED',
        voteId: data.voteId,
        data: {
          finalResults: data.results,
          totalVotes: data.totalVotes
        },
        timestamp: Date.now()
      });
    });

    // Decryption progress
    this.blockchainSync.on('decryptionShareSubmitted', (data) => {
      this.broadcastToVoteRoom(data.voteId, {
        type: 'ENCRYPTION_UPDATE',
        voteId: data.voteId,
        data: {
          shareIndex: data.shareIndex,
          progress: 'decryption_in_progress'
        },
        timestamp: Date.now()
      });
    });
  }

  /**
   * Broadcast message to all clients subscribed to a vote
   */
  private broadcastToVoteRoom(voteId: string, message: VoteUpdateMessage): void {
    this.io.to(`vote_${voteId}`).emit('vote_update', message);
    
    this.logger.info(`Broadcasted ${message.type} to vote room: ${voteId}`);
  }

  /**
   * Get current vote status from blockchain
   */
  private async getVoteStatus(voteId: string): Promise<any> {
    try {
      // Get vote details from blockchain
      const connectionStatus = await this.blockchainSync.getConnectionStatus();
      const encryptedTally = await this.blockchainSync.getEncryptedTally(voteId);
      
      return {
        connected: connectionStatus.connected,
        blockNumber: connectionStatus.blockNumber,
        totalVotes: encryptedTally.totalVotes,
        lastUpdated: encryptedTally.lastUpdated,
        isEncrypted: true
      };
    } catch (error) {
      this.logger.error('Failed to get vote status:', error);
      throw error;
    }
  }

  /**
   * Get server statistics
   */
  getServerStats(): {
    connectedClients: number;
    activeVotes: number;
    totalConnections: number;
    uptime: number;
  } {
    return {
      connectedClients: this.connections.size,
      activeVotes: this.rooms.size,
      totalConnections: this.connections.size,
      uptime: process.uptime()
    };
  }

  /**
   * Broadcast system message to all connected clients
   */
  broadcastSystemMessage(message: string, type: 'INFO' | 'WARNING' | 'ERROR' = 'INFO'): void {
    this.io.emit('system_message', {
      type,
      message,
      timestamp: Date.now()
    });
    
    this.logger.info(`Broadcasted system message: ${message}`);
  }

  /**
   * Close WebSocket server
   */
  close(): void {
    this.io.close();
    this.logger.info('WebSocket server closed');
  }
}