/**
 * Consultation Service
 * 
 * Handles clinical consultations, vital signs recording, diagnoses, and treatment plans.
 * This is a CRITICAL medical service with comprehensive safety features.
 * 
 * Port: 3005
 * 
 * @module consultation-service
 */

import express, { Request, Response, NextFunction } from 'express';
import { Pool, PoolClient } from 'pg';
import Redis from 'ioredis';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import compression from 'compression';
import morgan from 'morgan';
import { v4 as uuidv4 } from 'uuid';

// Import shared utilities
import { validateInput, ValidationSchema } from '../../shared/utils/validation';
import { AppError, handleError, asyncHandler } from '../../shared/utils/errors';
import { authenticateToken, requireRole } from '../../shared/middleware/auth';
import { auditLog } from '../../shared/middleware/audit';

// Initialize Express app
const app = express();

// Database connection pool
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME || 'hospital_management',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Redis client for caching
const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  password: process.env.REDIS_PASSWORD,
  retryStrategy: (times) => Math.min(times * 50, 2000),
});

// Middleware
app.use(helmet());
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
  credentials: true,
}));
app.use(compression());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(morgan('combined'));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // limit each IP to 1000 requests per windowMs
  message: 'Too many requests from this IP, please try again later.',
});
app.use('/api/', limiter);

// ============================================================================
// VALIDATION SCHEMAS
// ============================================================================

const vitalSignsSchema: ValidationSchema = {
  systolic_bp: { type: 'number', required: false, min: 60, max: 250 },
  diastolic_bp: { type: 'number', required: false, min: 40, max: 150 },
  pulse_rate: { type: 'number', required: false, min: 30, max: 250 },
  temperature: { type: 'number', required: false, min: 35, max: 43 },
  respiratory_rate: { type: 'number', required: false, min: 8, max: 60 },
  oxygen_saturation: { type: 'number', required: false, min: 70, max: 100 },
  weight: { type: 'number', required: false, min: 0.5, max: 500 },
  height: { type: 'number', required: false, min: 30, max: 250 },
};

const consultationSchema: ValidationSchema = {
  appointmentId: { type: 'string', required: true, format: 'uuid' },
  patientId: { type: 'string', required: true, format: 'uuid' },
  doctorId: { type: 'string', required: true, format: 'uuid' },
  chiefComplaint: { type: 'string', required: true, minLength: 5, maxLength: 1000 },
  presentingSymptoms: { type: 'string', required: false, maxLength: 5000 },
  vitalSigns: { type: 'object', required: false, schema: vitalSignsSchema },
};

const diagnosisSchema: ValidationSchema = {
  consultationId: { type: 'string', required: true, format: 'uuid' },
  icdCode: { type: 'string', required: true, pattern: /^[A-Z]\d{2}(\.\d{1,2})?$/ },
  diagnosisName: { type: 'string', required: true, minLength: 3, maxLength: 500 },
  diagnosisType: { type: 'string', required: true, enum: ['primary', 'secondary', 'differential'] },
  severity: { type: 'string', required: false, enum: ['mild', 'moderate', 'severe', 'critical'] },
  notes: { type: 'string', required: false, maxLength: 2000 },
};

const treatmentPlanSchema: ValidationSchema = {
  consultationId: { type: 'string', required: true, format: 'uuid' },
  planType: { type: 'string', required: true, enum: ['medication', 'procedure', 'therapy', 'lifestyle', 'follow-up'] },
  description: { type: 'string', required: true, minLength: 10, maxLength: 2000 },
  duration: { type: 'string', required: false, maxLength: 100 },
  instructions: { type: 'string', required: false, maxLength: 2000 },
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Generate unique consultation number
 */
async function generateConsultationNumber(): Promise<string> {
  const year = new Date().getFullYear();
  const result = await pool.query(
    `SELECT COUNT(*) as count FROM consultations 
     WHERE consultation_number LIKE $1`,
    [`CONS-${year}-%`]
  );
  const count = parseInt(result.rows[0].count) + 1;
  return `CONS-${year}-${String(count).padStart(6, '0')}`;
}

/**
 * Calculate BMI from weight and height
 */
function calculateBMI(weight: number, height: number): number {
  // weight in kg, height in cm
  const heightInMeters = height / 100;
  return parseFloat((weight / (heightInMeters * heightInMeters)).toFixed(2));
}

/**
 * Check if vital signs are critical
 */
function checkCriticalVitals(vitals: any): { isCritical: boolean; alerts: string[] } {
  const alerts: string[] = [];
  let isCritical = false;

  if (vitals.systolic_bp) {
    if (vitals.systolic_bp < 90 || vitals.systolic_bp > 180) {
      alerts.push(`Critical Blood Pressure: ${vitals.systolic_bp}/${vitals.diastolic_bp} mmHg`);
      isCritical = true;
    }
  }

  if (vitals.pulse_rate) {
    if (vitals.pulse_rate < 50 || vitals.pulse_rate > 120) {
      alerts.push(`Critical Pulse Rate: ${vitals.pulse_rate} bpm`);
      isCritical = true;
    }
  }

  if (vitals.temperature) {
    if (vitals.temperature < 36 || vitals.temperature > 39.5) {
      alerts.push(`Critical Temperature: ${vitals.temperature}°C`);
      isCritical = true;
    }
  }

  if (vitals.oxygen_saturation) {
    if (vitals.oxygen_saturation < 90) {
      alerts.push(`Critical Oxygen Saturation: ${vitals.oxygen_saturation}%`);
      isCritical = true;
    }
  }

  if (vitals.respiratory_rate) {
    if (vitals.respiratory_rate < 12 || vitals.respiratory_rate > 25) {
      alerts.push(`Critical Respiratory Rate: ${vitals.respiratory_rate} breaths/min`);
      isCritical = true;
    }
  }

  return { isCritical, alerts };
}

/**
 * Send critical alert notification
 */
async function sendCriticalAlert(patientId: string, doctorId: string, alerts: string[]): Promise<void> {
  try {
    // In production, this would send actual notifications via notification service
    console.log('CRITICAL ALERT:', {
      patientId,
      doctorId,
      alerts,
      timestamp: new Date().toISOString(),
    });

    // Store alert in database
    await pool.query(
      `INSERT INTO critical_alerts (patient_id, doctor_id, alert_type, alert_message, created_at)
       VALUES ($1, $2, 'vital_signs', $3, CURRENT_TIMESTAMP)`,
      [patientId, doctorId, JSON.stringify(alerts)]
    );
  } catch (error) {
    console.error('Error sending critical alert:', error);
  }
}

/**
 * Audit log for PHI access
 */
async function logPHIAccess(
  userId: string,
  action: string,
  resourceType: string,
  resourceId: string,
  ipAddress: string
): Promise<void> {
  try {
    await pool.query(
      `INSERT INTO audit_log (user_id, action, resource_type, resource_id, ip_address, created_at)
       VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)`,
      [userId, action, resourceType, resourceId, ipAddress]
    );
  } catch (error) {
    console.error('Error logging PHI access:', error);
  }
}

// ============================================================================
// API ENDPOINTS
// ============================================================================

/**
 * Health check endpoint
 */
app.get('/health', (req: Request, res: Response) => {
  res.json({
    success: true,
    service: 'consultation-service',
    status: 'healthy',
    timestamp: new Date().toISOString(),
  });
});

/**
 * Create new consultation
 * POST /api/v1/consultations
 */
app.post(
  '/api/v1/consultations',
  authenticateToken,
  requireRole(['doctor', 'nurse']),
  asyncHandler(async (req: Request, res: Response) => {
    // Validate input
    const validationErrors = validateInput(req.body, consultationSchema);
    if (validationErrors.length > 0) {
      throw new AppError('Validation failed', 400, validationErrors);
    }

    const {
      appointmentId,
      patientId,
      doctorId,
      chiefComplaint,
      presentingSymptoms,
      historyOfPresentIllness,
      pastMedicalHistory,
      familyHistory,
      socialHistory,
      reviewOfSystems,
      physicalExamination,
      vitalSigns,
      clinicalNotes,
    } = req.body;

    const client: PoolClient = await pool.connect();

    try {
      await client.query('BEGIN');

      // Verify appointment exists and is valid
      const appointmentResult = await client.query(
        `SELECT id, status FROM appointments WHERE id = $1 AND patient_id = $2 AND doctor_id = $3`,
        [appointmentId, patientId, doctorId]
      );

      if (appointmentResult.rows.length === 0) {
        throw new AppError('Appointment not found or invalid', 404);
      }

      if (appointmentResult.rows[0].status === 'completed') {
        throw new AppError('Appointment already completed', 400);
      }

      // Generate consultation number
      const consultationNumber = await generateConsultationNumber();

      // Calculate BMI if weight and height provided
      let bmi = null;
      if (vitalSigns?.weight && vitalSigns?.height) {
        bmi = calculateBMI(vitalSigns.weight, vitalSigns.height);
      }

      // Check for critical vital signs
      let criticalAlerts: string[] = [];
      if (vitalSigns) {
        const { isCritical, alerts } = checkCriticalVitals(vitalSigns);
        if (isCritical) {
          criticalAlerts = alerts;
          // Send critical alert
          await sendCriticalAlert(patientId, doctorId, alerts);
        }
      }

      // Create consultation record
      const consultationResult = await client.query(
        `INSERT INTO consultations (
          consultation_number, appointment_id, patient_id, doctor_id,
          chief_complaint, presenting_symptoms, history_of_present_illness,
          past_medical_history, family_history, social_history,
          review_of_systems, physical_examination,
          systolic_bp, diastolic_bp, pulse_rate, temperature,
          respiratory_rate, oxygen_saturation, weight, height, bmi,
          clinical_notes, status, created_by, created_at
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
          $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, 'in-progress', $23, CURRENT_TIMESTAMP
        ) RETURNING *`,
        [
          consultationNumber, appointmentId, patientId, doctorId,
          chiefComplaint, presentingSymptoms, historyOfPresentIllness,
          pastMedicalHistory, familyHistory, socialHistory,
          reviewOfSystems, physicalExamination,
          vitalSigns?.systolic_bp, vitalSigns?.diastolic_bp, vitalSigns?.pulse_rate,
          vitalSigns?.temperature, vitalSigns?.respiratory_rate, vitalSigns?.oxygen_saturation,
          vitalSigns?.weight, vitalSigns?.height, bmi,
          clinicalNotes, req.user.userId,
        ]
      );

      // Update appointment status
      await client.query(
        `UPDATE appointments SET status = 'in-consultation', updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [appointmentId]
      );

      await client.query('COMMIT');

      // Log PHI access
      await logPHIAccess(
        req.user.userId,
        'CREATE_CONSULTATION',
        'consultation',
        consultationResult.rows[0].id,
        req.ip
      );

      // Clear cache
      await redis.del(`consultation:${consultationResult.rows[0].id}`);
      await redis.del(`patient:${patientId}:consultations`);

      res.status(201).json({
        success: true,
        message: 'Consultation created successfully',
        data: {
          consultation: consultationResult.rows[0],
          criticalAlerts: criticalAlerts.length > 0 ? criticalAlerts : undefined,
        },
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  })
);

/**
 * Get consultation details
 * GET /api/v1/consultations/:id
 */
app.get(
  '/api/v1/consultations/:id',
  authenticateToken,
  asyncHandler(async (req: Request, res: Response) => {
    const { id } = req.params;

    // Check cache first
    const cached = await redis.get(`consultation:${id}`);
    if (cached) {
      await logPHIAccess(req.user.userId, 'VIEW_CONSULTATION', 'consultation', id, req.ip);
      return res.json({
        success: true,
        data: { consultation: JSON.parse(cached) },
        cached: true,
      });
    }

    // Query database
    const result = await pool.query(
      `SELECT c.*, 
        p.first_name || ' ' || p.last_name as patient_name,
        p.patient_number,
        d.first_name || ' ' || d.last_name as doctor_name,
        d.specialization,
        a.appointment_date,
        a.appointment_time,
        (SELECT json_agg(json_build_object(
          'id', cd.id,
          'icd_code', cd.icd_code,
          'diagnosis_name', cd.diagnosis_name,
          'diagnosis_type', cd.diagnosis_type,
          'severity', cd.severity,
          'notes', cd.notes
        )) FROM consultation_diagnoses cd WHERE cd.consultation_id = c.id) as diagnoses,
        (SELECT json_agg(json_build_object(
          'id', tp.id,
          'plan_type', tp.plan_type,
          'description', tp.description,
          'duration', tp.duration,
          'instructions', tp.instructions
        )) FROM treatment_plans tp WHERE tp.consultation_id = c.id) as treatment_plans
       FROM consultations c
       JOIN patients p ON c.patient_id = p.id
       JOIN doctors d ON c.doctor_id = d.id
       JOIN appointments a ON c.appointment_id = a.id
       WHERE c.id = $1 AND c.deleted_at IS NULL`,
      [id]
    );

    if (result.rows.length === 0) {
      throw new AppError('Consultation not found', 404);
    }

    const consultation = result.rows[0];

    // Cache for 5 minutes
    await redis.setex(`consultation:${id}`, 300, JSON.stringify(consultation));

    // Log PHI access
    await logPHIAccess(req.user.userId, 'VIEW_CONSULTATION', 'consultation', id, req.ip);

    res.json({
      success: true,
      data: { consultation },
    });
  })
);

/**
 * Update consultation
 * PUT /api/v1/consultations/:id
 */
app.put(
  '/api/v1/consultations/:id',
  authenticateToken,
  requireRole(['doctor', 'nurse']),
  asyncHandler(async (req: Request, res: Response) => {
    const { id } = req.params;
    const updates = req.body;

    const client: PoolClient = await pool.connect();

    try {
      await client.query('BEGIN');

      // Verify consultation exists and user has permission
      const consultationResult = await client.query(
        `SELECT id, doctor_id, status FROM consultations WHERE id = $1 AND deleted_at IS NULL`,
        [id]
      );

      if (consultationResult.rows.length === 0) {
        throw new AppError('Consultation not found', 404);
      }

      const consultation = consultationResult.rows[0];

      // Only the assigned doctor can update (unless admin)
      if (consultation.doctor_id !== req.user.userId && req.user.role !== 'admin') {
        throw new AppError('Unauthorized to update this consultation', 403);
      }

      if (consultation.status === 'completed') {
        throw new AppError('Cannot update completed consultation', 400);
      }

      // Build update query dynamically
      const allowedFields = [
        'chief_complaint', 'presenting_symptoms', 'history_of_present_illness',
        'past_medical_history', 'family_history', 'social_history',
        'review_of_systems', 'physical_examination', 'clinical_notes',
        'systolic_bp', 'diastolic_bp', 'pulse_rate', 'temperature',
        'respiratory_rate', 'oxygen_saturation', 'weight', 'height',
      ];

      const updateFields: string[] = [];
      const updateValues: any[] = [];
      let paramCount = 1;

      for (const field of allowedFields) {
        if (updates[field] !== undefined) {
          updateFields.push(`${field} = $${paramCount}`);
          updateValues.push(updates[field]);
          paramCount++;
        }
      }

      if (updateFields.length === 0) {
        throw new AppError('No valid fields to update', 400);
      }

      // Recalculate BMI if weight or height changed
      if (updates.weight || updates.height) {
        const currentData = await client.query(
          `SELECT weight, height FROM consultations WHERE id = $1`,
          [id]
        );
        const weight = updates.weight || currentData.rows[0].weight;
        const height = updates.height || currentData.rows[0].height;
        
        if (weight && height) {
          const bmi = calculateBMI(weight, height);
          updateFields.push(`bmi = $${paramCount}`);
          updateValues.push(bmi);
          paramCount++;
        }
      }

      updateFields.push(`updated_by = $${paramCount}`);
      updateValues.push(req.user.userId);
      paramCount++;

      updateFields.push(`updated_at = CURRENT_TIMESTAMP`);

      updateValues.push(id);

      const updateQuery = `
        UPDATE consultations 
        SET ${updateFields.join(', ')}
        WHERE id = $${paramCount}
        RETURNING *
      `;

      const result = await client.query(updateQuery, updateValues);

      await client.query('COMMIT');

      // Clear cache
      await redis.del(`consultation:${id}`);

      // Log PHI access
      await logPHIAccess(req.user.userId, 'UPDATE_CONSULTATION', 'consultation', id, req.ip);

      res.json({
        success: true,
        message: 'Consultation updated successfully',
        data: { consultation: result.rows[0] },
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  })
);

/**
 * Get patient consultation history
 * GET /api/v1/consultations/patient/:patientId
 */
app.get(
  '/api/v1/consultations/patient/:patientId',
  authenticateToken,
  asyncHandler(async (req: Request, res: Response) => {
    const { patientId } = req.params;
    const { page = 1, limit = 20, status } = req.query;

    const offset = (Number(page) - 1) * Number(limit);

    // Build query
    let query = `
      SELECT c.id, c.consultation_number, c.chief_complaint, c.status,
        c.created_at, c.updated_at,
        d.first_name || ' ' || d.last_name as doctor_name,
        d.specialization,
        a.appointment_date,
        a.appointment_time
      FROM consultations c
      JOIN doctors d ON c.doctor_id = d.id
      JOIN appointments a ON c.appointment_id = a.id
      WHERE c.patient_id = $1 AND c.deleted_at IS NULL
    `;

    const params: any[] = [patientId];
    let paramCount = 2;

    if (status) {
      query += ` AND c.status = $${paramCount}`;
      params.push(status);
      paramCount++;
    }

    query += ` ORDER BY c.created_at DESC LIMIT $${paramCount} OFFSET $${paramCount + 1}`;
    params.push(Number(limit), offset);

    const result = await pool.query(query, params);

    // Get total count
    const countResult = await pool.query(
      `SELECT COUNT(*) as total FROM consultations 
       WHERE patient_id = $1 AND deleted_at IS NULL ${status ? 'AND status = $2' : ''}`,
      status ? [patientId, status] : [patientId]
    );

    const total = parseInt(countResult.rows[0].total);

    // Log PHI access
    await logPHIAccess(
      req.user.userId,
      'VIEW_PATIENT_CONSULTATIONS',
      'patient',
      patientId,
      req.ip
    );

    res.json({
      success: true,
      data: {
        consultations: result.rows,
        pagination: {
          page: Number(page),
          limit: Number(limit),
          total,
          totalPages: Math.ceil(total / Number(limit)),
        },
      },
    });
  })
);

/**
 * Add diagnosis to consultation
 * POST /api/v1/consultations/:id/diagnoses
 */
app.post(
  '/api/v1/consultations/:id/diagnoses',
  authenticateToken,
  requireRole(['doctor']),
  asyncHandler(async (req: Request, res: Response) => {
    const { id: consultationId } = req.params;

    // Validate input
    const validationErrors = validateInput(
      { ...req.body, consultationId },
      diagnosisSchema
    );
    if (validationErrors.length > 0) {
      throw new AppError('Validation failed', 400, validationErrors);
    }

    const { icdCode, diagnosisName, diagnosisType, severity, notes } = req.body;

    const client: PoolClient = await pool.connect();

    try {
      await client.query('BEGIN');

      // Verify consultation exists and is not completed
      const consultationResult = await client.query(
        `SELECT id, doctor_id, status FROM consultations WHERE id = $1 AND deleted_at IS NULL`,
        [consultationId]
      );

      if (consultationResult.rows.length === 0) {
        throw new AppError('Consultation not found', 404);
      }

      const consultation = consultationResult.rows[0];

      if (consultation.doctor_id !== req.user.userId && req.user.role !== 'admin') {
        throw new AppError('Unauthorized to add diagnosis', 403);
      }

      if (consultation.status === 'completed') {
        throw new AppError('Cannot add diagnosis to completed consultation', 400);
      }

      // Check if primary diagnosis already exists
      if (diagnosisType === 'primary') {
        const existingPrimary = await client.query(
          `SELECT id FROM consultation_diagnoses 
           WHERE consultation_id = $1 AND diagnosis_type = 'primary' AND deleted_at IS NULL`,
          [consultationId]
        );

        if (existingPrimary.rows.length > 0) {
          throw new AppError('Primary diagnosis already exists for this consultation', 400);
        }
      }

      // Add diagnosis
      const result = await client.query(
        `INSERT INTO consultation_diagnoses (
          consultation_id, icd_code, diagnosis_name, diagnosis_type,
          severity, notes, created_by, created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP)
        RETURNING *`,
        [consultationId, icdCode, diagnosisName, diagnosisType, severity, notes, req.user.userId]
      );

      await client.query('COMMIT');

      // Clear cache
      await redis.del(`consultation:${consultationId}`);

      // Log PHI access
      await logPHIAccess(
        req.user.userId,
        'ADD_DIAGNOSIS',
        'consultation',
        consultationId,
        req.ip
      );

      res.status(201).json({
        success: true,
        message: 'Diagnosis added successfully',
        data: { diagnosis: result.rows[0] },
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  })
);

/**
 * Add treatment plan to consultation
 * POST /api/v1/consultations/:id/treatment-plans
 */
app.post(
  '/api/v1/consultations/:id/treatment-plans',
  authenticateToken,
  requireRole(['doctor']),
  asyncHandler(async (req: Request, res: Response) => {
    const { id: consultationId } = req.params;

    // Validate input
    const validationErrors = validateInput(
      { ...req.body, consultationId },
      treatmentPlanSchema
    );
    if (validationErrors.length > 0) {
      throw new AppError('Validation failed', 400, validationErrors);
    }

    const { planType, description, duration, instructions, priority } = req.body;

    const client: PoolClient = await pool.connect();

    try {
      await client.query('BEGIN');

      // Verify consultation exists
      const consultationResult = await client.query(
        `SELECT id, doctor_id, status FROM consultations WHERE id = $1 AND deleted_at IS NULL`,
        [consultationId]
      );

      if (consultationResult.rows.length === 0) {
        throw new AppError('Consultation not found', 404);
      }

      const consultation = consultationResult.rows[0];

      if (consultation.doctor_id !== req.user.userId && req.user.role !== 'admin') {
        throw new AppError('Unauthorized to add treatment plan', 403);
      }

      // Add treatment plan
      const result = await client.query(
        `INSERT INTO treatment_plans (
          consultation_id, plan_type, description, duration,
          instructions, priority, status, created_by, created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, 'active', $7, CURRENT_TIMESTAMP)
        RETURNING *`,
        [consultationId, planType, description, duration, instructions, priority, req.user.userId]
      );

      await client.query('COMMIT');

      // Clear cache
      await redis.del(`consultation:${consultationId}`);

      // Log PHI access
      await logPHIAccess(
        req.user.userId,
        'ADD_TREATMENT_PLAN',
        'consultation',
        consultationId,
        req.ip
      );

      res.status(201).json({
        success: true,
        message: 'Treatment plan added successfully',
        data: { treatmentPlan: result.rows[0] },
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  })
);

/**
 * Complete consultation
 * PUT /api/v1/consultations/:id/complete
 */
app.put(
  '/api/v1/consultations/:id/complete',
  authenticateToken,
  requireRole(['doctor']),
  asyncHandler(async (req: Request, res: Response) => {
    const { id } = req.params;
    const { summary, followUpDate, followUpInstructions } = req.body;

    const client: PoolClient = await pool.connect();

    try {
      await client.query('BEGIN');

      // Verify consultation exists
      const consultationResult = await client.query(
        `SELECT c.*, a.id as appointment_id
         FROM consultations c
         JOIN appointments a ON c.appointment_id = a.id
         WHERE c.id = $1 AND c.deleted_at IS NULL`,
        [id]
      );

      if (consultationResult.rows.length === 0) {
        throw new AppError('Consultation not found', 404);
      }

      const consultation = consultationResult.rows[0];

      if (consultation.doctor_id !== req.user.userId && req.user.role !== 'admin') {
        throw new AppError('Unauthorized to complete this consultation', 403);
      }

      if (consultation.status === 'completed') {
        throw new AppError('Consultation already completed', 400);
      }

      // Check if at least one diagnosis exists
      const diagnosisResult = await client.query(
        `SELECT COUNT(*) as count FROM consultation_diagnoses
         WHERE consultation_id = $1 AND deleted_at IS NULL`,
        [id]
      );

      if (parseInt(diagnosisResult.rows[0].count) === 0) {
        throw new AppError('At least one diagnosis is required to complete consultation', 400);
      }

      // Update consultation status
      const result = await client.query(
        `UPDATE consultations 
         SET status = 'completed',
             consultation_summary = $1,
             follow_up_date = $2,
             follow_up_instructions = $3,
             completed_at = CURRENT_TIMESTAMP,
             updated_by = $4,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $5
         RETURNING *`,
        [summary, followUpDate, followUpInstructions, req.user.userId, id]
      );

      // Update appointment status
      await client.query(
        `UPDATE appointments 
         SET status = 'completed', updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [consultation.appointment_id]
      );

      await client.query('COMMIT');

      // Clear cache
      await redis.del(`consultation:${id}`);

      // Log PHI access
      await logPHIAccess(
        req.user.userId,
        'COMPLETE_CONSULTATION',
        'consultation',
        id,
        req.ip
      );

      res.json({
        success: true,
        message: 'Consultation completed successfully',
        data: { consultation: result.rows[0] },
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  })
);

/**
 * Generate medical certificate
 * GET /api/v1/consultations/:id/certificate
 */
app.get(
  '/api/v1/consultations/:id/certificate',
  authenticateToken,
  requireRole(['doctor']),
  asyncHandler(async (req: Request, res: Response) => {
    const { id } = req.params;

    // Get consultation details
    const result = await pool.query(
      `SELECT c.*, 
        p.first_name || ' ' || p.last_name as patient_name,
        p.date_of_birth,
        p.patient_number,
        d.first_name || ' ' || d.last_name as doctor_name,
        d.medical_license_number,
        d.specialization,
        a.appointment_date
       FROM consultations c
       JOIN patients p ON c.patient_id = p.id
       JOIN doctors d ON c.doctor_id = d.id
       JOIN appointments a ON c.appointment_id = a.id
       WHERE c.id = $1 AND c.deleted_at IS NULL`,
      [id]
    );

    if (result.rows.length === 0) {
      throw new AppError('Consultation not found', 404);
    }

    const consultation = result.rows[0];

    if (consultation.doctor_id !== req.user.userId && req.user.role !== 'admin') {
      throw new AppError('Unauthorized to generate certificate', 403);
    }

    if (consultation.status !== 'completed') {
      throw new AppError('Consultation must be completed to generate certificate', 400);
    }

    // Generate certificate data
    const certificate = {
      certificateNumber: `CERT-${new Date().getFullYear()}-${uuidv4().substring(0, 8).toUpperCase()}`,
      issueDate: new Date().toISOString(),
      patientName: consultation.patient_name,
      patientNumber: consultation.patient_number,
      dateOfBirth: consultation.date_of_birth,
      consultationDate: consultation.appointment_date,
      diagnosis: consultation.consultation_summary,
      recommendations: consultation.follow_up_instructions,
      doctorName: consultation.doctor_name,
      doctorLicense: consultation.medical_license_number,
      specialization: consultation.specialization,
      hospitalName: process.env.HOSPITAL_NAME || 'Hospital Management System',
    };

    // Log PHI access
    await logPHIAccess(
      req.user.userId,
      'GENERATE_CERTIFICATE',
      'consultation',
      id,
      req.ip
    );

    res.json({
      success: true,
      data: { certificate },
    });
  })
);

/**
 * Search consultations
 * GET /api/v1/consultations/search
 */
app.get(
  '/api/v1/consultations/search',
  authenticateToken,
  asyncHandler(async (req: Request, res: Response) => {
    const { query, startDate, endDate, doctorId, status, page = 1, limit = 20 } = req.query;

    const offset = (Number(page) - 1) * Number(limit);

    let searchQuery = `
      SELECT c.id, c.consultation_number, c.chief_complaint, c.status,
        c.created_at,
        p.first_name || ' ' || p.last_name as patient_name,
        p.patient_number,
        d.first_name || ' ' || d.last_name as doctor_name,
        d.specialization
      FROM consultations c
      JOIN patients p ON c.patient_id = p.id
      JOIN doctors d ON c.doctor_id = d.id
      WHERE c.deleted_at IS NULL
    `;

    const params: any[] = [];
    let paramCount = 1;

    if (query) {
      searchQuery += ` AND (
        c.chief_complaint ILIKE $${paramCount} OR
        c.clinical_notes ILIKE $${paramCount} OR
        p.first_name ILIKE $${paramCount} OR
        p.last_name ILIKE $${paramCount}
      )`;
      params.push(`%${query}%`);
      paramCount++;
    }

    if (startDate) {
      searchQuery += ` AND c.created_at >= $${paramCount}`;
      params.push(startDate);
      paramCount++;
    }

    if (endDate) {
      searchQuery += ` AND c.created_at <= $${paramCount}`;
      params.push(endDate);
      paramCount++;
    }

    if (doctorId) {
      searchQuery += ` AND c.doctor_id = $${paramCount}`;
      params.push(doctorId);
      paramCount++;
    }

    if (status) {
      searchQuery += ` AND c.status = $${paramCount}`;
      params.push(status);
      paramCount++;
    }

    searchQuery += ` ORDER BY c.created_at DESC LIMIT $${paramCount} OFFSET $${paramCount + 1}`;
    params.push(Number(limit), offset);

    const result = await pool.query(searchQuery, params);

    res.json({
      success: true,
      data: {
        consultations: result.rows,
        pagination: {
          page: Number(page),
          limit: Number(limit),
        },
      },
    });
  })
);

// ============================================================================
// ERROR HANDLING
// ============================================================================

// 404 handler
app.use((req: Request, res: Response) => {
  res.status(404).json({
    success: false,
    error: 'Endpoint not found',
  });
});

// Global error handler
app.use((err: any, req: Request, res: Response, next: NextFunction) => {
  handleError(err, res);
});

// ============================================================================
// SERVER STARTUP
// ============================================================================

const PORT = process.env.CONSULTATION_SERVICE_PORT || 3005;

app.listen(PORT, () => {
  console.log(`✅ Consultation Service running on port ${PORT}`);
  console.log(`🏥 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`📊 Database: ${process.env.DB_NAME || 'hospital_management'}`);
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM signal received: closing HTTP server');
  await pool.end();
  await redis.quit();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('SIGINT signal received: closing HTTP server');
  await pool.end();
  await redis.quit();
  process.exit(0);
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason: any, promise: Promise<any>) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

export default app;
