/**
 * Doctor Service
 * CRITICAL: Manages doctor profiles, schedules, and availability
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
} from '../../../shared/utils/errors';
import {
  validateRequest,
  sanitizeString,
  validateDateRange,
} from '../../../shared/utils/validation';

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
 * Health check
 */
app.get('/health', (req: Request, res: Response) => {
  res.json({
    success: true,
    service: 'doctor-service',
    status: 'healthy',
    timestamp: new Date().toISOString(),
  });
});

/**
 * Get all doctors
 */
app.get('/', asyncHandler(async (req: Request, res: Response) => {
  const { specialization, department, available, page = 1, limit = 20 } = req.query;
  
  const offset = (Number(page) - 1) * Number(limit);
  
  let queryText = `
    SELECT 
      d.id, d.doctor_code, d.first_name, d.last_name, d.specialization,
      d.qualification, d.experience_years, d.phone, d.email,
      d.consultation_fee, d.is_available, d.rating,
      dep.name as department_name
    FROM clinical.doctors d
    LEFT JOIN core.departments dep ON d.department_id = dep.id
    WHERE d.is_active = true
  `;
  
  const params: any[] = [];
  let paramCount = 1;
  
  if (specialization) {
    queryText += ` AND d.specialization = $${paramCount}`;
    params.push(specialization);
    paramCount++;
  }
  
  if (department) {
    queryText += ` AND d.department_id = $${paramCount}`;
    params.push(department);
    paramCount++;
  }
  
  if (available === 'true') {
    queryText += ` AND d.is_available = true`;
  }
  
  queryText += ` ORDER BY d.last_name, d.first_name LIMIT $${paramCount} OFFSET $${paramCount + 1}`;
  params.push(limit, offset);
  
  try {
    const result = await query(queryText, params);
    
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
 * Get doctor by ID
 */
app.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  
  // Check cache
  const cached = await cache.get(`doctor:${id}`);
  if (cached) {
    return res.json({
      success: true,
      data: cached,
      cached: true,
    });
  }
  
  try {
    const result = await query(
      `SELECT 
        d.id, d.doctor_code, d.first_name, d.last_name, d.specialization,
        d.qualification, d.experience_years, d.phone, d.email, d.gender,
        d.date_of_birth, d.license_number, d.consultation_fee,
        d.is_available, d.rating, d.total_consultations,
        d.languages_spoken, d.bio, d.created_at,
        dep.name as department_name
       FROM clinical.doctors d
       LEFT JOIN core.departments dep ON d.department_id = dep.id
       WHERE d.id = $1 AND d.is_active = true`,
      [id]
    );
    
    if (result.rows.length === 0) {
      throw new NotFoundError('Doctor');
    }
    
    const doctor = result.rows[0];
    
    // Cache doctor data
    await cache.set(`doctor:${id}`, doctor, 3600);
    
    res.json({
      success: true,
      data: doctor,
    });
  } catch (error) {
    if (error instanceof NotFoundError) {
      throw error;
    }
    throw handleDatabaseError(error);
  }
}));

/**
 * Get doctor availability
 */
app.get('/:id/availability', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const { date, startDate, endDate } = req.query;
  
  try {
    let queryText = `
      SELECT 
        id, doctor_id, day_of_week, start_time, end_time,
        slot_duration, max_patients_per_slot, is_available
      FROM clinical.doctor_schedules
      WHERE doctor_id = $1 AND is_active = true
    `;
    
    const params: any[] = [id];
    
    if (date) {
      // Get availability for specific date
      const dayOfWeek = new Date(date as string).toLocaleDateString('en-US', { weekday: 'lowercase' });
      queryText += ` AND day_of_week = $2`;
      params.push(dayOfWeek);
    }
    
    queryText += ` ORDER BY 
      CASE day_of_week
        WHEN 'monday' THEN 1
        WHEN 'tuesday' THEN 2
        WHEN 'wednesday' THEN 3
        WHEN 'thursday' THEN 4
        WHEN 'friday' THEN 5
        WHEN 'saturday' THEN 6
        WHEN 'sunday' THEN 7
      END, start_time`;
    
    const schedules = await query(queryText, params);
    
    // Check for leaves
    let leaves = { rows: [] };
    if (startDate && endDate) {
      leaves = await query(
        `SELECT leave_date, leave_type, reason
         FROM clinical.doctor_leaves
         WHERE doctor_id = $1 
         AND leave_date BETWEEN $2 AND $3
         AND status = 'approved'`,
        [id, startDate, endDate]
      );
    }
    
    res.json({
      success: true,
      data: {
        schedules: schedules.rows,
        leaves: leaves.rows,
      },
    });
  } catch (error) {
    throw handleDatabaseError(error);
  }
}));

/**
 * Update doctor schedule
 */
app.post('/:id/schedule', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const { dayOfWeek, startTime, endTime, slotDuration, maxPatientsPerSlot } = req.body;
  
  if (!dayOfWeek || !startTime || !endTime) {
    throw new ValidationError('Day of week, start time, and end time are required');
  }
  
  try {
    // Check if schedule already exists
    const existing = await query(
      `SELECT id FROM clinical.doctor_schedules 
       WHERE doctor_id = $1 AND day_of_week = $2 AND is_active = true`,
      [id, dayOfWeek.toLowerCase()]
    );
    
    let result;
    
    if (existing.rows.length > 0) {
      // Update existing schedule
      result = await query(
        `UPDATE clinical.doctor_schedules
         SET start_time = $1, end_time = $2, slot_duration = $3,
             max_patients_per_slot = $4, updated_at = NOW()
         WHERE doctor_id = $5 AND day_of_week = $6
         RETURNING id, day_of_week, start_time, end_time, slot_duration`,
        [startTime, endTime, slotDuration || 30, maxPatientsPerSlot || 1, id, dayOfWeek.toLowerCase()]
      );
    } else {
      // Create new schedule
      result = await query(
        `INSERT INTO clinical.doctor_schedules (
          doctor_id, day_of_week, start_time, end_time, slot_duration, max_patients_per_slot
        ) VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, day_of_week, start_time, end_time, slot_duration`,
        [id, dayOfWeek.toLowerCase(), startTime, endTime, slotDuration || 30, maxPatientsPerSlot || 1]
      );
    }
    
    // Invalidate cache
    await cache.del(`doctor:${id}`);
    
    res.status(201).json({
      success: true,
      message: 'Schedule updated successfully',
      data: result.rows[0],
    });
  } catch (error) {
    throw handleDatabaseError(error);
  }
}));

/**
 * Request leave
 */
app.post('/:id/leave', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const { leaveDate, leaveType, reason } = req.body;
  
  if (!leaveDate || !leaveType) {
    throw new ValidationError('Leave date and type are required');
  }
  
  try {
    // Check if leave already exists for this date
    const existing = await query(
      `SELECT id FROM clinical.doctor_leaves 
       WHERE doctor_id = $1 AND leave_date = $2`,
      [id, leaveDate]
    );
    
    if (existing.rows.length > 0) {
      throw new ConflictError('Leave already requested for this date');
    }
    
    const result = await query(
      `INSERT INTO clinical.doctor_leaves (
        doctor_id, leave_date, leave_type, reason, status
      ) VALUES ($1, $2, $3, $4, 'pending')
      RETURNING id, leave_date, leave_type, status, created_at`,
      [id, leaveDate, leaveType, reason || null]
    );
    
    res.status(201).json({
      success: true,
      message: 'Leave request submitted successfully',
      data: result.rows[0],
    });
  } catch (error) {
    if (error instanceof ConflictError) {
      throw error;
    }
    throw handleDatabaseError(error);
  }
}));

/**
 * Get doctor statistics
 */
app.get('/:id/statistics', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const { startDate, endDate } = req.query;
  
  try {
    // Get consultation statistics
    const consultations = await query(
      `SELECT 
        COUNT(*) as total_consultations,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN status = 'cancelled' THEN 1 END) as cancelled,
        AVG(CASE WHEN status = 'completed' THEN duration END) as avg_duration
       FROM clinical.consultations
       WHERE doctor_id = $1
       ${startDate && endDate ? 'AND consultation_date BETWEEN $2 AND $3' : ''}`,
      startDate && endDate ? [id, startDate, endDate] : [id]
    );
    
    // Get appointment statistics
    const appointments = await query(
      `SELECT 
        COUNT(*) as total_appointments,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN status = 'no_show' THEN 1 END) as no_shows
       FROM clinical.appointments
       WHERE doctor_id = $1
       ${startDate && endDate ? 'AND appointment_date BETWEEN $2 AND $3' : ''}`,
      startDate && endDate ? [id, startDate, endDate] : [id]
    );
    
    res.json({
      success: true,
      data: {
        consultations: consultations.rows[0],
        appointments: appointments.rows[0],
      },
    });
  } catch (error) {
    throw handleDatabaseError(error);
  }
}));

/**
 * Search doctors
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
        d.id, d.doctor_code, d.first_name, d.last_name, d.specialization,
        d.qualification, d.phone, d.email, d.consultation_fee, d.rating
       FROM clinical.doctors d
       WHERE d.is_active = true
       AND (
         d.first_name ILIKE $1 OR
         d.last_name ILIKE $1 OR
         d.doctor_code ILIKE $1 OR
         d.specialization ILIKE $1
       )
       ORDER BY d.rating DESC, d.last_name, d.first_name
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
const PORT = process.env.DOCTOR_SERVICE_PORT || 3003;

async function startServer() {
  try {
    await initializeDatabase();
    
    app.listen(PORT, () => {
      console.log(`👨‍⚕️ Doctor Service running on port ${PORT}`);
      console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
    });
  } catch (error) {
    console.error('Failed to start doctor service:', error);
    process.exit(1);
  }
}

startServer();

export default app;
