/**
 * Enhanced Logger for Biometric DAO System
 * Provides structured logging with security event tracking
 */

import winston from 'winston';
import path from 'path';

export interface SecurityEvent {
  type: 'AUTHENTICATION_FAILURE' | 'UNAUTHORIZED_ACCESS' | 'BIOMETRIC_MISMATCH' | 'VOTE_TAMPERING' | 'ENCRYPTION_ERROR';
  severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  details: Record<string, any>;
  timestamp: number;
  source: string;
}

export class Logger {
  private winston: winston.Logger;
  private component: string;

  constructor(component: string) {
    this.component = component;
    this.winston = winston.createLogger({
      level: process.env.LOG_LEVEL || 'info',
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json()
      ),
      defaultMeta: { 
        service: 'biometric-dao',
        component: this.component
      },
      transports: [
        new winston.transports.File({ 
          filename: path.join('logs', 'error.log'), 
          level: 'error' 
        }),
        new winston.transports.File({ 
          filename: path.join('logs', 'combined.log') 
        }),
        new winston.transports.File({
          filename: path.join('logs', 'security.log'),
          level: 'warn'
        })
      ]
    });

    // Add console transport in development
    if (process.env.NODE_ENV !== 'production') {
      this.winston.add(new winston.transports.Console({
        format: winston.format.combine(
          winston.format.colorize(),
          winston.format.simple()
        )
      }));
    }
  }

  info(message: string, meta?: any): void {
    this.winston.info(message, { ...meta, component: this.component });
  }

  warn(message: string, meta?: any): void {
    this.winston.warn(message, { ...meta, component: this.component });
  }

  error(message: string, error?: any, meta?: any): void {
    this.winston.error(message, { 
      error: error?.stack || error, 
      ...meta, 
      component: this.component 
    });
  }

  debug(message: string, meta?: any): void {
    this.winston.debug(message, { ...meta, component: this.component });
  }

  security(event: SecurityEvent): void {
    this.winston.warn('SECURITY_EVENT', {
      securityEvent: event,
      component: this.component,
      timestamp: new Date().toISOString()
    });
  }

  audit(action: string, user: string, details?: any): void {
    this.winston.info('AUDIT_LOG', {
      action,
      user,
      details,
      component: this.component,
      timestamp: new Date().toISOString()
    });
  }
}