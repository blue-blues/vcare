/**
 * Authentication Service
 * CRITICAL: Handles all authentication and authorization
 * Security is paramount - any breach can compromise patient data
 */

import express, { Request, Response, NextFunction } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import speakeasy from 'speakeasy';
import QRCode from 'qrcode';
import { v4 as uuidv4 } from 'uuid';
import dotenv from 'dotenv';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import morgan from 'morgan';

import { pool, query, transaction, cache, initializeDatabase } from '../../../shared/config/database';
import { 
  ValidationError, 
  AuthenticationError, 
  AuthorizationError,
  ConflictError,
  NotFoundError,
  formatErrorResponse,
  asyncHandler,
  logError,
  handleDatabaseError
} from '../../../shared/utils/errors';
import { 
  validateRequest, 
  userSchemas,
  sanitizeString,
  hasSQLInjection
} from '../../../shared/utils/validation';

// Load environment variables
dotenv.config();

const app = express();

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
  credentials: true,
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(morgan('combined'));

// Rate limiting
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5, // 5 attempts
  message: 'Too many login attempts, please try again later',
  standardHeaders: true,
  legacyHeaders: false,
});

const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 3, // 3 registrations
  message: 'Too many registration attempts, please try again later',
});

// JWT configuration
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '24h';
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'your-refresh-secret-change-in-production';
const JWT_REFRESH_EXPIRES_IN = process.env.JWT_REFRESH_EXPIRES_IN || '7d';

// Bcrypt configuration
const SALT_ROUNDS = 12;

/**
 * Interfaces
 */
interface RegisterRequest {
  username: string;
  email: string;
  password: string;
  userType: 'patient' | 'doctor' | 'nurse' | 'admin' | 'staff';
  firstName: string;
  lastName: string;
  phone: string;
  dateOfBirth: string;
  gender: 'male' | 'female' | 'other';
}

interface LoginRequest {
  username: string;
  password: string;
  mfaToken?: string;
}

interface TokenPayload {
  userId: string;
  username: string;
  userType: string;
  sessionId: string;
}

/**
 * Helper Functions
 */

/**
 * Generate JWT token
 */
function generateToken(payload: TokenPayload): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}

/**
 * Generate refresh token
 */
function generateRefreshToken(payload: TokenPayload): string {
  return jwt.sign(payload, JWT_REFRESH_SECRET, { expiresIn: JWT_REFRESH_EXPIRES_IN });
}

/**
 * Verify JWT token
 */
function verifyToken(token: string): TokenPayload {
  try {
    return jwt.verify(token, JWT_SECRET) as TokenPayload;
  } catch (error) {
    throw new AuthenticationError('Invalid or expired token');
  }
}

/**
 * Hash password
 */
async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, SALT_ROUNDS);
}

/**
 * Compare password
 */
async function comparePassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash);
}

/**
 * Create session
 */
async function createSession(userId: string, userAgent: string, ipAddress: string): Promise<string> {
  const sessionId = uuidv4();
  const expiresAt = new Date();
  expiresAt.setHours(expiresAt.getHours() + 24);
  
  await query(
    `INSERT INTO core.sessions (id, user_id, session_token, user_agent, ip_address, expires_at)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [sessionId, userId, sessionId, userAgent, ipAddress, expiresAt]
  );
  
  // Store in Redis for fast access
  await cache.set(`session:${sessionId}`, { userId, userAgent, ipAddress }, 86400); // 24 hours
  
  return sessionId;
}

/**
 * Log authentication event
 */
async function logAuthEvent(
  userId: string | null,
  eventType: string,
  success: boolean,
  ipAddress: string,
  userAgent: string,
  details?: any
): Promise<void> {
  await query(
    `INSERT INTO audit.security_events (user_id, event_type, success, ip_address, user_agent, details)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [userId, eventType, success, ipAddress, userAgent, JSON.stringify(details || {})]
  );
}

/**
 * Check if account is locked
 */
async function isAccountLocked(userId: string): Promise<boolean> {
  const result = await query(
    `SELECT locked_until FROM core.users WHERE id = $1`,
    [userId]
  );
  
  if (result.rows.length === 0) return false;
  
  const lockedUntil = result.rows[0].locked_until;
  if (!lockedUntil) return false;
  
  return new Date(lockedUntil) > new Date();
}

/**
 * Increment failed login attempts
 */
async function incrementFailedAttempts(userId: string): Promise<void> {
  const result = await query(
    `UPDATE core.users 
     SET failed_login_attempts = failed_login_attempts + 1,
         locked_until = CASE 
           WHEN failed_login_attempts + 1 >= 5 THEN NOW() + INTERVAL '30 minutes'
           ELSE locked_until
         END
     WHERE id = $1
     RETURNING failed_login_attempts`,
    [userId]
  );
  
  if (result.rows[0].failed_login_attempts >= 5) {
    console.warn(`Account locked due to failed attempts: ${userId}`);
  }
}

/**
 * Reset failed login attempts
 */
async function resetFailedAttempts(userId: string): Promise<void> {
  await query(
    `UPDATE core.users 
     SET failed_login_attempts = 0, locked_until = NULL 
     WHERE id = $1`,
    [userId]
  );
}

/**
 * Routes
 */

/**
 * Health check
 */
app.get('/health', (req: Request, res: Response) => {
  res.json({ 
    success: true, 
    service: 'auth-service',
    status: 'healthy',
    timestamp: new Date().toISOString()
  });
});

/**
 * Register new user
 */
app.post('/register', registerLimiter, asyncHandler(async (req: Request, res: Response) => {
  // Validate request
  const { error, value } = validateRequest(userSchemas.register, req.body);
  if (error) {
    throw new ValidationError(error);
  }
  
  const data: RegisterRequest = value;
  
  // Check for SQL injection
  if (hasSQLInjection(data.username) || hasSQLInjection(data.email)) {
    throw new ValidationError('Invalid input detected');
  }
  
  // Sanitize inputs
  data.username = sanitizeString(data.username);
  data.email = sanitizeString(data.email);
  data.firstName = sanitizeString(data.firstName);
  data.lastName = sanitizeString(data.lastName);
  
  try {
    // Check if username or email already exists
    const existingUser = await query(
      `SELECT id FROM core.users WHERE username = $1 OR email = $2`,
      [data.username, data.email]
    );
    
    if (existingUser.rows.length > 0) {
      throw new ConflictError('Username or email already exists');
    }
    
    // Hash password
    const passwordHash = await hashPassword(data.password);
    
    // Create user in transaction
    const result = await transaction(async (client) => {
      // Insert user
      const userResult = await client.query(
        `INSERT INTO core.users (username, email, password_hash, user_type, is_active, is_verified)
         VALUES ($1, $2, $3, $4, true, false)
         RETURNING id, username, email, user_type, created_at`,
        [data.username, data.email, passwordHash, data.userType]
      );
      
      const user = userResult.rows[0];
      
      // Insert user profile based on type
      if (data.userType === 'patient') {
        await client.query(
          `INSERT INTO clinical.patients (user_id, first_name, last_name, date_of_birth, gender, phone, email)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [user.id, data.firstName, data.lastName, data.dateOfBirth, data.gender, data.phone, data.email]
        );
      } else if (data.userType === 'doctor') {
        await client.query(
          `INSERT INTO clinical.doctors (user_id, first_name, last_name, phone, email, gender)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [user.id, data.firstName, data.lastName, data.phone, data.email, data.gender]
        );
      } else if (data.userType === 'nurse' || data.userType === 'staff') {
        await client.query(
          `INSERT INTO clinical.staff (user_id, first_name, last_name, staff_type, phone, email, gender)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [user.id, data.firstName, data.lastName, data.userType, data.phone, data.email, data.gender]
        );
      }
      
      return user;
    });
    
    // Log registration event
    await logAuthEvent(
      result.id,
      'user_registered',
      true,
      req.ip || 'unknown',
      req.get('user-agent') || 'unknown',
      { userType: data.userType }
    );
    
    res.status(201).json({
      success: true,
      message: 'User registered successfully',
      data: {
        id: result.id,
        username: result.username,
        email: result.email,
        userType: result.user_type,
        createdAt: result.created_at,
      },
    });
  } catch (error) {
    if (error instanceof ConflictError || error instanceof ValidationError) {
      throw error;
    }
    throw handleDatabaseError(error);
  }
}));

/**
 * Login
 */
app.post('/login', loginLimiter, asyncHandler(async (req: Request, res: Response) => {
  // Validate request
  const { error, value } = validateRequest(userSchemas.login, req.body);
  if (error) {
    throw new ValidationError(error);
  }
  
  const { username, password, mfaToken }: LoginRequest = value;
  
  try {
    // Get user
    const result = await query(
      `SELECT id, username, email, password_hash, user_type, is_active, is_verified, 
              two_factor_enabled, two_factor_secret, failed_login_attempts, locked_until
       FROM core.users 
       WHERE username = $1 OR email = $1`,
      [username]
    );
    
    if (result.rows.length === 0) {
      await logAuthEvent(null, 'login_failed', false, req.ip || 'unknown', req.get('user-agent') || 'unknown', { reason: 'user_not_found' });
      throw new AuthenticationError('Invalid credentials');
    }
    
    const user = result.rows[0];
    
    // Check if account is active
    if (!user.is_active) {
      await logAuthEvent(user.id, 'login_failed', false, req.ip || 'unknown', req.get('user-agent') || 'unknown', { reason: 'account_inactive' });
      throw new AuthenticationError('Account is inactive');
    }
    
    // Check if account is locked
    if (await isAccountLocked(user.id)) {
      await logAuthEvent(user.id, 'login_failed', false, req.ip || 'unknown', req.get('user-agent') || 'unknown', { reason: 'account_locked' });
      throw new AuthenticationError('Account is temporarily locked due to multiple failed login attempts');
    }
    
    // Verify password
    const passwordValid = await comparePassword(password, user.password_hash);
    if (!passwordValid) {
      await incrementFailedAttempts(user.id);
      await logAuthEvent(user.id, 'login_failed', false, req.ip || 'unknown', req.get('user-agent') || 'unknown', { reason: 'invalid_password' });
      throw new AuthenticationError('Invalid credentials');
    }
    
    // Check MFA if enabled
    if (user.two_factor_enabled) {
      if (!mfaToken) {
        return res.status(200).json({
          success: true,
          requiresMFA: true,
          message: 'MFA token required',
        });
      }
      
      const verified = speakeasy.totp.verify({
        secret: user.two_factor_secret,
        encoding: 'base32',
        token: mfaToken,
        window: 2,
      });
      
      if (!verified) {
        await incrementFailedAttempts(user.id);
        await logAuthEvent(user.id, 'login_failed', false, req.ip || 'unknown', req.get('user-agent') || 'unknown', { reason: 'invalid_mfa' });
        throw new AuthenticationError('Invalid MFA token');
      }
    }
    
    // Reset failed attempts
    await resetFailedAttempts(user.id);
    
    // Create session
    const sessionId = await createSession(user.id, req.get('user-agent') || 'unknown', req.ip || 'unknown');
    
    // Generate tokens
    const tokenPayload: TokenPayload = {
      userId: user.id,
      username: user.username,
      userType: user.user_type,
      sessionId,
    };
    
    const accessToken = generateToken(tokenPayload);
    const refreshToken = generateRefreshToken(tokenPayload);
    
    // Update last login
    await query(
      `UPDATE core.users SET last_login = NOW() WHERE id = $1`,
      [user.id]
    );
    
    // Log successful login
    await logAuthEvent(user.id, 'login_success', true, req.ip || 'unknown', req.get('user-agent') || 'unknown');
    
    res.json({
      success: true,
      message: 'Login successful',
      data: {
        user: {
          id: user.id,
          username: user.username,
          email: user.email,
          userType: user.user_type,
        },
        accessToken,
        refreshToken,
        expiresIn: JWT_EXPIRES_IN,
      },
    });
  } catch (error) {
    if (error instanceof AuthenticationError || error instanceof ValidationError) {
      throw error;
    }
    throw handleDatabaseError(error);
  }
}));

/**
 * Logout
 */
app.post('/logout', asyncHandler(async (req: Request, res: Response) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  
  if (!token) {
    throw new AuthenticationError('No token provided');
  }
  
  try {
    const payload = verifyToken(token);
    
    // Invalidate session
    await query(
      `UPDATE core.sessions SET is_active = false WHERE id = $1`,
      [payload.sessionId]
    );
    
    // Remove from cache
    await cache.del(`session:${payload.sessionId}`);
    
    // Log logout
    await logAuthEvent(payload.userId, 'logout', true, req.ip || 'unknown', req.get('user-agent') || 'unknown');
    
    res.json({
      success: true,
      message: 'Logout successful',
    });
  } catch (error) {
    throw new AuthenticationError('Invalid token');
  }
}));

/**
 * Verify token
 */
app.post('/verify', asyncHandler(async (req: Request, res: Response) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  
  if (!token) {
    throw new AuthenticationError('No token provided');
  }
  
  try {
    const payload = verifyToken(token);
    
    // Check if session is still active
    const sessionActive = await cache.exists(`session:${payload.sessionId}`);
    if (!sessionActive) {
      throw new AuthenticationError('Session expired');
    }
    
    res.json({
      success: true,
      data: {
        userId: payload.userId,
        username: payload.username,
        userType: payload.userType,
      },
    });
  } catch (error) {
    throw new AuthenticationError('Invalid or expired token');
  }
}));

/**
 * Setup MFA
 */
app.post('/mfa/setup', asyncHandler(async (req: Request, res: Response) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  
  if (!token) {
    throw new AuthenticationError('No token provided');
  }
  
  const payload = verifyToken(token);
  
  // Generate secret
  const secret = speakeasy.generateSecret({
    name: `HMS:${payload.username}`,
    issuer: 'Hospital Management System',
    length: 32,
  });
  
  // Generate QR code
  const qrCode = await QRCode.toDataURL(secret.otpauth_url!);
  
  // Store secret (encrypted in production)
  await query(
    `UPDATE core.users SET two_factor_secret = $1 WHERE id = $2`,
    [secret.base32, payload.userId]
  );
  
  res.json({
    success: true,
    data: {
      secret: secret.base32,
      qrCode,
    },
  });
}));

/**
 * Enable MFA
 */
app.post('/mfa/enable', asyncHandler(async (req: Request, res: Response) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  const { mfaToken } = req.body;
  
  if (!token) {
    throw new AuthenticationError('No token provided');
  }
  
  if (!mfaToken) {
    throw new ValidationError('MFA token required');
  }
  
  const payload = verifyToken(token);
  
  // Get user's secret
  const result = await query(
    `SELECT two_factor_secret FROM core.users WHERE id = $1`,
    [payload.userId]
  );
  
  if (result.rows.length === 0 || !result.rows[0].two_factor_secret) {
    throw new ValidationError('MFA not set up');
  }
  
  // Verify token
  const verified = speakeasy.totp.verify({
    secret: result.rows[0].two_factor_secret,
    encoding: 'base32',
    token: mfaToken,
    window: 2,
  });
  
  if (!verified) {
    throw new ValidationError('Invalid MFA token');
  }
  
  // Enable MFA
  await query(
    `UPDATE core.users SET two_factor_enabled = true WHERE id = $1`,
    [payload.userId]
  );
  
  await logAuthEvent(payload.userId, 'mfa_enabled', true, req.ip || 'unknown', req.get('user-agent') || 'unknown');
  
  res.json({
    success: true,
    message: 'MFA enabled successfully',
  });
}));

/**
 * Error handling middleware
 */
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  logError(err, {
    path: req.path,
    method: req.method,
    body: req.body,
    ip: req.ip,
  });
  
  const errorResponse = formatErrorResponse(err, req.path);
  res.status(errorResponse.error.statusCode).json(errorResponse);
});

/**
 * Start server
 */
const PORT = process.env.AUTH_SERVICE_PORT || 3001;

async function startServer() {
  try {
    // Initialize database connections
    await initializeDatabase();
    
    app.listen(PORT, () => {
      console.log(`🔐 Auth Service running on port ${PORT}`);
      console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
    });
  } catch (error) {
    console.error('Failed to start auth service:', error);
    process.exit(1);
  }
}

startServer();

export default app;
