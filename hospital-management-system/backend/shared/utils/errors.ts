/**
 * Error Handling Utilities
 * CRITICAL: Proper error handling prevents system crashes and data loss
 */

/**
 * Custom error classes for different error types
 */

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly isOperational: boolean;
  public readonly code?: string;
  
  constructor(
    message: string,
    statusCode: number = 500,
    isOperational: boolean = true,
    code?: string
  ) {
    super(message);
    
    this.statusCode = statusCode;
    this.isOperational = isOperational;
    this.code = code;
    
    // Maintains proper stack trace for where error was thrown
    Error.captureStackTrace(this, this.constructor);
    
    // Set the prototype explicitly
    Object.setPrototypeOf(this, AppError.prototype);
  }
}

/**
 * Validation Error (400)
 */
export class ValidationError extends AppError {
  constructor(message: string, code?: string) {
    super(message, 400, true, code || 'VALIDATION_ERROR');
    Object.setPrototypeOf(this, ValidationError.prototype);
  }
}

/**
 * Authentication Error (401)
 */
export class AuthenticationError extends AppError {
  constructor(message: string = 'Authentication failed', code?: string) {
    super(message, 401, true, code || 'AUTHENTICATION_ERROR');
    Object.setPrototypeOf(this, AuthenticationError.prototype);
  }
}

/**
 * Authorization Error (403)
 */
export class AuthorizationError extends AppError {
  constructor(message: string = 'Access denied', code?: string) {
    super(message, 403, true, code || 'AUTHORIZATION_ERROR');
    Object.setPrototypeOf(this, AuthorizationError.prototype);
  }
}

/**
 * Not Found Error (404)
 */
export class NotFoundError extends AppError {
  constructor(resource: string, code?: string) {
    super(`${resource} not found`, 404, true, code || 'NOT_FOUND');
    Object.setPrototypeOf(this, NotFoundError.prototype);
  }
}

/**
 * Conflict Error (409)
 */
export class ConflictError extends AppError {
  constructor(message: string, code?: string) {
    super(message, 409, true, code || 'CONFLICT');
    Object.setPrototypeOf(this, ConflictError.prototype);
  }
}

/**
 * Database Error (500)
 */
export class DatabaseError extends AppError {
  constructor(message: string = 'Database operation failed', code?: string) {
    super(message, 500, true, code || 'DATABASE_ERROR');
    Object.setPrototypeOf(this, DatabaseError.prototype);
  }
}

/**
 * External Service Error (502)
 */
export class ExternalServiceError extends AppError {
  constructor(service: string, message?: string, code?: string) {
    super(
      message || `External service ${service} is unavailable`,
      502,
      true,
      code || 'EXTERNAL_SERVICE_ERROR'
    );
    Object.setPrototypeOf(this, ExternalServiceError.prototype);
  }
}

/**
 * Rate Limit Error (429)
 */
export class RateLimitError extends AppError {
  constructor(message: string = 'Too many requests', code?: string) {
    super(message, 429, true, code || 'RATE_LIMIT_EXCEEDED');
    Object.setPrototypeOf(this, RateLimitError.prototype);
  }
}

/**
 * Medical Error - Critical medical operation failure
 */
export class MedicalError extends AppError {
  constructor(message: string, code?: string) {
    super(message, 500, true, code || 'MEDICAL_ERROR');
    Object.setPrototypeOf(this, MedicalError.prototype);
  }
}

/**
 * Error response interface
 */
export interface ErrorResponse {
  success: false;
  error: {
    message: string;
    code?: string;
    statusCode: number;
    details?: any;
    timestamp: string;
    path?: string;
  };
}

/**
 * Format error response
 */
export function formatErrorResponse(
  error: AppError | Error,
  path?: string,
  details?: any
): ErrorResponse {
  const isAppError = error instanceof AppError;
  
  return {
    success: false,
    error: {
      message: error.message,
      code: isAppError ? error.code : 'INTERNAL_ERROR',
      statusCode: isAppError ? error.statusCode : 500,
      details: process.env.NODE_ENV === 'development' ? details : undefined,
      timestamp: new Date().toISOString(),
      path,
    },
  };
}

/**
 * Check if error is operational (expected) or programming error
 */
export function isOperationalError(error: Error): boolean {
  if (error instanceof AppError) {
    return error.isOperational;
  }
  return false;
}

/**
 * Handle database errors and convert to AppError
 */
export function handleDatabaseError(error: any): AppError {
  // PostgreSQL error codes
  const pgErrorCodes: { [key: string]: { message: string; statusCode: number } } = {
    '23505': { message: 'Duplicate entry. Record already exists', statusCode: 409 },
    '23503': { message: 'Referenced record not found', statusCode: 404 },
    '23502': { message: 'Required field is missing', statusCode: 400 },
    '23514': { message: 'Check constraint violation', statusCode: 400 },
    '22P02': { message: 'Invalid input syntax', statusCode: 400 },
    '42P01': { message: 'Table does not exist', statusCode: 500 },
    '42703': { message: 'Column does not exist', statusCode: 500 },
  };
  
  const pgError = pgErrorCodes[error.code];
  
  if (pgError) {
    return new AppError(pgError.message, pgError.statusCode, true, error.code);
  }
  
  // Connection errors
  if (error.code === 'ECONNREFUSED' || error.code === 'ETIMEDOUT') {
    return new DatabaseError('Database connection failed', 'DB_CONNECTION_ERROR');
  }
  
  // Default database error
  return new DatabaseError(
    process.env.NODE_ENV === 'development' ? error.message : 'Database operation failed',
    'DATABASE_ERROR'
  );
}

/**
 * Async error wrapper for route handlers
 */
export function asyncHandler(fn: Function) {
  return (req: any, res: any, next: any) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

/**
 * Log error with context
 */
export function logError(error: Error, context?: any): void {
  const errorLog = {
    message: error.message,
    stack: error.stack,
    timestamp: new Date().toISOString(),
    context,
  };
  
  if (error instanceof AppError) {
    errorLog['statusCode'] = error.statusCode;
    errorLog['code'] = error.code;
    errorLog['isOperational'] = error.isOperational;
  }
  
  // In production, this would go to a logging service (Winston, etc.)
  console.error('Error:', JSON.stringify(errorLog, null, 2));
}

/**
 * Critical error handler - for life-threatening situations
 */
export function handleCriticalError(
  error: Error,
  context: {
    patientId?: string;
    operation: string;
    userId?: string;
  }
): void {
  // Log critical error
  console.error('CRITICAL ERROR:', {
    error: error.message,
    stack: error.stack,
    context,
    timestamp: new Date().toISOString(),
  });
  
  // In production:
  // 1. Send immediate alert to on-call staff
  // 2. Log to critical error monitoring system
  // 3. Create incident ticket
  // 4. Notify relevant medical staff if patient-related
  
  // For now, just log
  console.error('⚠️  CRITICAL: Immediate attention required!');
}

/**
 * Validate critical operation before execution
 */
export function validateCriticalOperation(
  operation: string,
  data: any,
  requiredFields: string[]
): void {
  const missingFields = requiredFields.filter(field => !data[field]);
  
  if (missingFields.length > 0) {
    throw new ValidationError(
      `Critical operation ${operation} missing required fields: ${missingFields.join(', ')}`,
      'CRITICAL_VALIDATION_ERROR'
    );
  }
}

/**
 * Safe JSON parse with error handling
 */
export function safeJSONParse<T>(json: string, defaultValue: T): T {
  try {
    return JSON.parse(json);
  } catch (error) {
    logError(error as Error, { json });
    return defaultValue;
  }
}

/**
 * Retry mechanism for critical operations
 */
export async function retryOperation<T>(
  operation: () => Promise<T>,
  maxRetries: number = 3,
  delayMs: number = 1000
): Promise<T> {
  let lastError: Error;
  
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error as Error;
      
      if (attempt < maxRetries) {
        console.warn(`Operation failed (attempt ${attempt}/${maxRetries}), retrying...`);
        await new Promise(resolve => setTimeout(resolve, delayMs * attempt));
      }
    }
  }
  
  throw new AppError(
    `Operation failed after ${maxRetries} attempts: ${lastError!.message}`,
    500,
    true,
    'RETRY_EXHAUSTED'
  );
}

/**
 * Circuit breaker for external services
 */
export class CircuitBreaker {
  private failureCount: number = 0;
  private lastFailureTime: number = 0;
  private state: 'CLOSED' | 'OPEN' | 'HALF_OPEN' = 'CLOSED';
  
  constructor(
    private readonly threshold: number = 5,
    private readonly timeout: number = 60000 // 1 minute
  ) {}
  
  async execute<T>(operation: () => Promise<T>): Promise<T> {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailureTime > this.timeout) {
        this.state = 'HALF_OPEN';
      } else {
        throw new ExternalServiceError(
          'Service',
          'Circuit breaker is OPEN',
          'CIRCUIT_BREAKER_OPEN'
        );
      }
    }
    
    try {
      const result = await operation();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }
  
  private onSuccess(): void {
    this.failureCount = 0;
    this.state = 'CLOSED';
  }
  
  private onFailure(): void {
    this.failureCount++;
    this.lastFailureTime = Date.now();
    
    if (this.failureCount >= this.threshold) {
      this.state = 'OPEN';
      console.error('Circuit breaker opened due to repeated failures');
    }
  }
  
  getState(): string {
    return this.state;
  }
}

/**
 * Error codes for medical operations
 */
export const MedicalErrorCodes = {
  DRUG_INTERACTION: 'DRUG_INTERACTION_DETECTED',
  ALLERGY_CONFLICT: 'ALLERGY_CONFLICT',
  CRITICAL_VITALS: 'CRITICAL_VITAL_SIGNS',
  DOSAGE_ERROR: 'DOSAGE_ERROR',
  PRESCRIPTION_CONFLICT: 'PRESCRIPTION_CONFLICT',
  LAB_CRITICAL_VALUE: 'LAB_CRITICAL_VALUE',
  APPOINTMENT_CONFLICT: 'APPOINTMENT_CONFLICT',
  BED_UNAVAILABLE: 'BED_UNAVAILABLE',
  EMERGENCY_ALERT: 'EMERGENCY_ALERT',
} as const;

/**
 * Validate medical operation safety
 */
export function validateMedicalSafety(
  operation: string,
  checks: {
    drugInteractions?: boolean;
    allergies?: boolean;
    vitalSigns?: boolean;
    dosage?: boolean;
  }
): void {
  const failures: string[] = [];
  
  if (checks.drugInteractions === false) {
    failures.push('Drug interaction detected');
  }
  
  if (checks.allergies === false) {
    failures.push('Allergy conflict detected');
  }
  
  if (checks.vitalSigns === false) {
    failures.push('Critical vital signs detected');
  }
  
  if (checks.dosage === false) {
    failures.push('Dosage validation failed');
  }
  
  if (failures.length > 0) {
    throw new MedicalError(
      `Medical safety check failed for ${operation}: ${failures.join(', ')}`,
      'MEDICAL_SAFETY_CHECK_FAILED'
    );
  }
}
