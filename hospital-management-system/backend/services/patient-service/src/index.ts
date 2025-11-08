/**
 * Patient Service
 * CRITICAL: Handles all patient-related operations
 * PHI (Protected Health Information) - HIPAA compliance required
 */

import express, { Request, Response, NextFunction } from 'express';
import dotenv from 'dotenv';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';

import { pool, query, transaction, cache, initializeDatabase } from '../../../shared/config/database';
import {
  ValidationError,
  NotFoundError,
  ConflictError,
  formatErrorResponse,
  asyncHandler,
  logError,
  handleDatabaseError,
  MedicalError,
  validateCriticalOperation,
} from '../../../shared/utils/errors';
import {
  validateRequest,
  patientSchemas,
  sanitizeString,
  calculateAge,
  calculateBMI,
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

/**
 * Interfaces
 */
interface CreatePatientRequest {
  firstName: string;
  lastName: string;
  dateOfBirth: string;
  gender: 'male' | 'female' | 'other';
  bloodGroup?: string;
  phone: string;
  email?: string;
  emergencyContactName: string;
  emergencyContactPhone: string;
  emergencyContactRelationship: string;
  address: {
    line1: string;
    line2?: string;
    city: string;
    state: string;
    country: string;
    postalCode: string;
  };
}

interface AddAllergyRequest {
  allergen: string;
  allergyType: 'drug' | 'food' | 'environmental' | 'other';
  severity: 'mild' | 'moderate' | 'severe' | 'life_threatening';
  reaction: string;
  onsetDate?: string;
  notes?: string;
}

/**
 * Helper Functions
 */

/**
 * Generate patient MRN (Medical Record Number)
 */
async function generateMRN(): Promise<string> {
  const year = new Date().getFullYear();
  const result = await query(
    `SELECT COUNT(*) as count FROM clinical.patients 
     WHERE mrn LIKE $1`,
    [`MRN-${year}-%`]
  );
  const count = parseInt(result.rows[0].count) + 1;
  return `MRN-${year}-${String(count).padStart(6, '0')}`;
}

/**
 * Log PHI access for HIPAA compliance
 */
async function logPHIAccess(
  userId: string,
  patientId: string,
  action: string,
  ipAddress: string
): Promise<void> {
  await query(
    `INSERT INTO audit.phi_access_log (user_id, patient_id, action, ip_address, accessed_at)
     VALUES ($1, $2, $3, $4, NOW())`,
    [userId, patientId, action, ipAddress]
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
    service: 'patient-service',
    status: 'healthy',
    timestamp: new Date().toISOString(),
  });
});

/**
 * Create new patient
 */
app.post('/', asyncHandler(async (req: Request, res: Response) => {
  // Validate request
  const { error, value } = validateRequest(patientSchemas.create, req.body);
  if (error) {
    throw new ValidationError(error);
  }
  
  const data: CreatePatientRequest = value;
  
  // Sanitize inputs
  data.firstName = sanitizeString(data.firstName);
  data.lastName = sanitizeString(data.lastName);
  
  try {
    // Check if patient already exists (by phone or email)
    const existing = await query(
      `SELECT id FROM clinical.patients 
       WHERE phone = $1 OR (email IS NOT NULL AND email = $2)`,
      [data.phone, data.email || null]
    );
    
    if (existing.rows.length > 0) {
      throw new ConflictError('Patient with this phone or email already exists');
    }
    
    // Generate MRN
    const mrn = await generateMRN();
    
    // Calculate age
    const age = calculateAge(new Date(data.dateOfBirth));
    
    // Create patient in transaction
    const result = await transaction(async (client) => {
      // Insert patient
      const patientResult = await client.query(
        `INSERT INTO clinical.patients (
          mrn, first_name, last_name, date_of_birth, age, gender, blood_group,
          phone, email, emergency_contact_name, emergency_contact_phone,
          emergency_contact_relationship, address_line1, address_line2,
          city, state, country, postal_code, registration_date
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, NOW())
        RETURNING id, mrn, first_name, last_name, date_of_birth, age, gender, 
                  blood_group, phone, email, registration_date, created_at`,
        [
          mrn,
          data.firstName,
          data.lastName,
          data.dateOfBirth,
          age,
          data.gender,
          data.bloodGroup || null,
          data.phone,
          data.email || null,
          data.emergencyContactName,
          data.emergencyContactPhone,
          data.emergencyContactRelationship,
          data.address.line1,
          data.address.line2 || null,
          data.address.city,
          data.address.state,
          data.address.country,
          data.address.postalCode,
        ]
      );
      
      return patientResult.rows[0];
    });
    
    // Cache patient data
    await cache.set(`patient:${result.id}`, result, 3600); // 1 hour
    
    res.status(201).json({
      success: true,
      message: 'Patient registered successfully',
      data: result,
    });
  } catch (error) {
    if (error instanceof ConflictError || error instanceof ValidationError) {
      throw error;
    }
    throw handleDatabaseError(error);
  }
}));

/**
 * Get patient by ID
 */
app.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  
  // Check cache first
  const cached = await cache.get(`patient:${id}`);
  if (cached) {
    // Log PHI access
    await logPHIAccess(
      req.user?.userId || 'system',
      id,
      'view_patient',
      req.ip || 'unknown'
    );
    
    return res.json({
      success: true,
      data: cached,
      cached: true,
    });
  }
  
  try {
    const result = await query(
      `SELECT 
        id, mrn, first_name, last_name, date_of_birth, age, gender, blood_group,
        phone, email, emergency_contact_name, emergency_contact_phone,
        emergency_contact_relationship, address_line1, address_line2,
        city, state, country, postal_code, registration_date,
        is_active, created_at, updated_at
       FROM clinical.patients
       WHERE id = $1 AND is_active = true`,
      [id]
    );
    
    if (result.rows.length === 0) {
      throw new NotFoundError('Patient');
    }
    
    const patient = result.rows[0];
    
    // Cache patient data
    await cache.set(`patient:${id}`, patient, 3600);
    
    // Log PHI access
    await logPHIAccess(
      req.user?.userId || 'system',
      id,
      'view_patient',
      req.ip || 'unknown'
    );
    
    res.json({
      success: true,
      data: patient,
    });
  } catch (error) {
    if (error instanceof NotFoundError) {
      throw error;
    }
    throw handleDatabaseError(error);
  }
}));

/**
 * Update patient
 */
app.put('/:id', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const updates = req.body;
  
  // Validate critical operation
  validateCriticalOperation('update_patient', updates, ['id']);
  
  try {
    // Check if patient exists
    const existing = await query(
      `SELECT id FROM clinical.patients WHERE id = $1 AND is_active = true`,
      [id]
    );
    
    if (existing.rows.length === 0) {
      throw new NotFoundError('Patient');
    }
    
    // Build update query dynamically
    const allowedFields = [
      'phone', 'email', 'emergency_contact_name', 'emergency_contact_phone',
      'emergency_contact_relationship', 'address_line1', 'address_line2',
      'city', 'state', 'country', 'postal_code'
    ];
    
    const updateFields: string[] = [];
    const values: any[] = [];
    let paramCount = 1;
    
    Object.keys(updates).forEach(key => {
      if (allowedFields.includes(key)) {
        updateFields.push(`${key} = $${paramCount}`);
        values.push(updates[key]);
        paramCount++;
      }
    });
    
    if (updateFields.length === 0) {
      throw new ValidationError('No valid fields to update');
    }
    
    values.push(id);
    
    const result = await query(
      `UPDATE clinical.patients 
       SET ${updateFields.join(', ')}, updated_at = NOW()
       WHERE id = $${paramCount}
       RETURNING id, mrn, first_name, last_name, phone, email, updated_at`,
      values
    );
    
    // Invalidate cache
    await cache.del(`patient:${id}`);
    
    // Log PHI access
    await logPHIAccess(
      req.user?.userId || 'system',
      id,
      'update_patient',
      req.ip || 'unknown'
    );
    
    res.json({
      success: true,
      message: 'Patient updated successfully',
      data: result.rows[0],
    });
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof ValidationError) {
      throw error;
    }
    throw handleDatabaseError(error);
  }
}));

/**
 * Get patient medical history
 */
app.get('/:id/medical-history', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  
  try {
    const result = await query(
      `SELECT 
        id, condition_name, diagnosis_date, status, severity,
        treatment, notes, diagnosed_by, created_at
       FROM clinical.medical_history
       WHERE patient_id = $1
       ORDER BY diagnosis_date DESC`,
      [id]
    );
    
    // Log PHI access
    await logPHIAccess(
      req.user?.userId || 'system',
      id,
      'view_medical_history',
      req.ip || 'unknown'
    );
    
    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    throw handleDatabaseError(error);
  }
}));

/**
 * Add medical history
 */
app.post('/:id/medical-history', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const { conditionName, diagnosisDate, status, severity, treatment, notes } = req.body;
  
  // Validate critical medical operation
  validateCriticalOperation('add_medical_history', req.body, [
    'conditionName',
    'diagnosisDate',
  ]);
  
  try {
    const result = await query(
      `INSERT INTO clinical.medical_history (
        patient_id, condition_name, diagnosis_date, status, severity,
        treatment, notes, diagnosed_by
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING id, condition_name, diagnosis_date, status, severity, created_at`,
      [
        id,
        sanitizeString(conditionName),
        diagnosisDate,
        status || 'active',
        severity || 'moderate',
        treatment || null,
        notes || null,
        req.user?.userId || null,
      ]
    );
    
    // Log PHI access
    await logPHIAccess(
      req.user?.userId || 'system',
      id,
      'add_medical_history',
      req.ip || 'unknown'
    );
    
    res.status(201).json({
      success: true,
      message: 'Medical history added successfully',
      data: result.rows[0],
    });
  } catch (error) {
    throw handleDatabaseError(error);
  }
}));

/**
 * Get patient allergies
 */
app.get('/:id/allergies', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  
  try {
    const result = await query(
      `SELECT 
        id, allergen, allergy_type, severity, reaction,
        onset_date, notes, is_active, created_at
       FROM clinical.allergies
       WHERE patient_id = $1 AND is_active = true
       ORDER BY severity DESC, created_at DESC`,
      [id]
    );
    
    // Log PHI access
    await logPHIAccess(
      req.user?.userId || 'system',
      id,
      'view_allergies',
      req.ip || 'unknown'
    );
    
    res.json({
      success: true,
      data: result.rows,
    });
  } catch (error) {
    throw handleDatabaseError(error);
  }
}));

/**
 * Add allergy (CRITICAL - can be life-threatening)
 */
app.post('/:id/allergies', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  
  // Validate request
  const { error, value } = validateRequest(patientSchemas.addAllergy, req.body);
  if (error) {
    throw new ValidationError(error);
  }
  
  const data: AddAllergyRequest = value;
  
  // CRITICAL: Validate this is a critical medical operation
  validateCriticalOperation('add_allergy', data, ['allergen', 'allergyType', 'severity', 'reaction']);
  
  try {
    // Check for duplicate allergy
    const existing = await query(
      `SELECT id FROM clinical.allergies 
       WHERE patient_id = $1 AND allergen = $2 AND is_active = true`,
      [id, data.allergen]
    );
    
    if (existing.rows.length > 0) {
      throw new ConflictError('This allergy is already recorded for the patient');
    }
    
    const result = await query(
      `INSERT INTO clinical.allergies (
        patient_id, allergen, allergy_type, severity, reaction,
        onset_date, notes, recorded_by
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING id, allergen, allergy_type, severity, reaction, onset_date, created_at`,
      [
        id,
        sanitizeString(data.allergen),
        data.allergyType,
        data.severity,
        sanitizeString(data.reaction),
        data.onsetDate || null,
        data.notes || null,
        req.user?.userId || null,
      ]
    );
    
    // CRITICAL: If life-threatening, create alert
    if (data.severity === 'life_threatening') {
      await query(
        `INSERT INTO clinical.critical_alerts (
          alert_type, severity, patient_id, alert_message, parameter_name, parameter_value
        ) VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          'allergy',
          'critical',
          id,
          `Life-threatening allergy added: ${data.allergen}`,
          'allergen',
          data.allergen,
        ]
      );
    }
    
    // Invalidate cache
    await cache.del(`patient:${id}`);
    
    // Log PHI access
    await logPHIAccess(
      req.user?.userId || 'system',
      id,
      'add_allergy',
      req.ip || 'unknown'
    );
    
    res.status(201).json({
      success: true,
      message: 'Allergy added successfully',
      data: result.rows[0],
      warning: data.severity === 'life_threatening' ? 'CRITICAL: Life-threatening allergy recorded' : undefined,
    });
  } catch (error) {
    if (error instanceof ConflictError || error instanceof ValidationError) {
      throw error;
    }
    throw handleDatabaseError(error);
  }
}));

/**
 * Search patients
 */
app.get('/search', asyncHandler(async (req: Request, res: Response) => {
  const { query: searchQuery, page = 1, limit = 20 } = req.query;
  
  if (!searchQuery) {
    throw new ValidationError('Search query is required');
  }
  
  const offset = (Number(page) - 1) * Number(limit);
  
  try {
    const result = await query(
      `SELECT 
        id, mrn, first_name, last_name, date_of_birth, age, gender,
        phone, email, registration_date
       FROM clinical.patients
       WHERE is_active = true
       AND (
         first_name ILIKE $1 OR
         last_name ILIKE $1 OR
         mrn ILIKE $1 OR
         phone ILIKE $1 OR
         email ILIKE $1
       )
       ORDER BY last_name, first_name
       LIMIT $2 OFFSET $3`,
      [`%${searchQuery}%`, limit, offset]
    );
    
    res.json({
      success: true,
      data: result.rows,
      pagination: {
        page: Number(page),
        limit: Number(limit),
        total: result.rowCount,
      },
    });
  } catch (error) {
    throw handleDatabaseError(error);
  }
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
const PORT = process.env.PATIENT_SERVICE_PORT || 3002;

async function startServer() {
  try {
    // Initialize database connections
    await initializeDatabase();
    
    app.listen(PORT, () => {
      console.log(`👥 Patient Service running on port ${PORT}`);
      console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
    });
  } catch (error) {
    console.error('Failed to start patient service:', error);
    process.exit(1);
  }
}

startServer();

// Extend Express Request type
declare global {
  namespace Express {
    interface Request {
      user?: {
        userId: string;
        username: string;
        userType: string;
      };
    }
  }
}

export default app;
