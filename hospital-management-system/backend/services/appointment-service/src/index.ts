/**
 * Appointment Service
 * CRITICAL: Manages appointment booking, scheduling, and queue management
 * Prevents double-booking and ensures optimal resource utilization
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
  validateCriticalOperation,
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
 * Interfaces
 */
interface CreateAppointmentRequest {
  patientId: string;
  doctorId: string;
  appointmentDate: string;
  appointmentTime: string;
  appointmentType: 'consultation' | 'follow_up' | 'emergency' | 'routine_checkup';
  reason: string;
  notes?: string;
}

/**
 * Helper Functions
 */

/**
 * Check if doctor is available at the requested time
 * CRITICAL: Prevents double-booking
 */
async function checkDoctorAvailability(
  doctorId: string,
  appointmentDate: string,
  appointmentTime: string
): Promise<{ available: boolean; reason?: string }> {
  // Check if doctor has a schedule for this day
  const dayOfWeek = new Date(appointmentDate).toLocaleDateString('en-US', { weekday: 'long' }).toLowerCase();
  
  const schedule = await query(
    `SELECT start_time, end_time, slot_duration, max_patients_per_slot
     FROM clinical.doctor_schedules
     WHERE doctor_id = $1 AND day_of_week = $2 AND is_available = true AND is_active = true`,
    [doctorId, dayOfWeek]
  );
  
  if (schedule.rows.length === 0) {
    return { available: false, reason: 'Doctor not available on this day' };
  }
  
  const { start_time, end_time, max_patients_per_slot } = schedule.rows[0];
  
  // Check if time is within schedule
  if (appointmentTime < start_time || appointmentTime >= end_time) {
    return { available: false, reason: 'Time outside doctor\'s schedule' };
  }
  
  // Check for leaves
  const leave = await query(
    `SELECT id FROM clinical.doctor_leaves
     WHERE doctor_id = $1 AND leave_date = $2 AND status = 'approved'`,
    [doctorId, appointmentDate]
  );
  
  if (leave.rows.length > 0) {
    return { available: false, reason: 'Doctor on leave' };
  }
  
  // Check existing appointments at this time
  const existing = await query(
    `SELECT COUNT(*) as count
     FROM clinical.appointments
     WHERE doctor_id = $1 
     AND appointment_date = $2 
     AND appointment_time = $3
     AND status NOT IN ('cancelled', 'no_show')`,
    [doctorId, appointmentDate, appointmentTime]
  );
  
  if (parseInt(existing.rows[0].count) >= max_patients_per_slot) {
    return { available: false, reason: 'Time slot fully booked' };
  }
  
  return { available: true };
}

/**
 * Calculate queue position
 */
async function calculateQueuePosition(
  doctorId: string,
  appointmentDate: string
): Promise<number> {
  const result = await query(
    `SELECT COALESCE(MAX(queue_position), 0) + 1 as position
     FROM clinical.appointment_queue
     WHERE doctor_id = $1 AND appointment_date = $2`,
    [doctorId, appointmentDate]
  );
  
  return result.rows[0].position;
}

/**
 * Send appointment reminder (placeholder)
 */
async function sendAppointmentReminder(appointmentId: string): Promise<void> {
  // TODO: Implement email/SMS notification
  console.log(`Reminder scheduled for appointment: ${appointmentId}`);
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
    service: 'appointment-service',
    status: 'healthy',
    timestamp: new Date().toISOString(),
  });
});

/**
 * Create appointment
 * CRITICAL: Must prevent double-booking
 */
app.post('/', asyncHandler(async (req: Request, res: Response) => {
  const data: CreateAppointmentRequest = req.body;
  
  // Validate critical operation
  validateCriticalOperation('create_appointment', data, [
    'patientId',
    'doctorId',
    'appointmentDate',
    'appointmentTime',
    'appointmentType',
    'reason',
  ]);
  
  // Validate date is not in the past
  const appointmentDateTime = new Date(`${data.appointmentDate}T${data.appointmentTime}`);
  if (appointmentDateTime < new Date()) {
    throw new ValidationError('Cannot book appointment in the past');
  }
  
  try {
    // Check doctor availability
    const availability = await checkDoctorAvailability(
      data.doctorId,
      data.appointmentDate,
      data.appointmentTime
    );
    
    if (!availability.available) {
      throw new ConflictError(availability.reason || 'Time slot not available');
    }
    
    // Create appointment in transaction
    const result = await transaction(async (client) => {
      // Generate appointment number
      const appointmentNumber = await client.query(
        `SELECT generate_appointment_number() as number`
      );
      
      // Insert appointment
      const appointment = await client.query(
        `INSERT INTO clinical.appointments (
          appointment_number, patient_id, doctor_id, appointment_date,
          appointment_time, appointment_type, reason, notes, status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'scheduled')
        RETURNING id, appointment_number, patient_id, doctor_id, appointment_date,
                  appointment_time, appointment_type, status, created_at`,
        [
          appointmentNumber.rows[0].number,
          data.patientId,
          data.doctorId,
          data.appointmentDate,
          data.appointmentTime,
          data.appointmentType,
          sanitizeString(data.reason),
          data.notes ? sanitizeString(data.notes) : null,
        ]
      );
      
      // Calculate queue position
      const queuePosition = await calculateQueuePosition(data.doctorId, data.appointmentDate);
      
      // Add to queue
      await client.query(
        `INSERT INTO clinical.appointment_queue (
          appointment_id, patient_id, doctor_id, appointment_date,
          queue_position, status
        ) VALUES ($1, $2, $3, $4, $5, 'waiting')`,
        [
          appointment.rows[0].id,
          data.patientId,
          data.doctorId,
          data.appointmentDate,
          queuePosition,
        ]
      );
      
      return {
        ...appointment.rows[0],
        queuePosition,
      };
    });
    
    // Schedule reminder
    await sendAppointmentReminder(result.id);
    
    res.status(201).json({
      success: true,
      message: 'Appointment booked successfully',
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
 * Get appointment by ID
 */
app.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  
  try {
    const result = await query(
      `SELECT 
        a.id, a.appointment_number, a.patient_id, a.doctor_id,
        a.appointment_date, a.appointment_time, a.appointment_type,
        a.reason, a.notes, a.status, a.created_at,
        p.first_name as patient_first_name, p.last_name as patient_last_name,
        p.phone as patient_phone,
        d.first_name as doctor_first_name, d.last_name as doctor_last_name,
        d.specialization as doctor_specialization,
        q.queue_position, q.status as queue_status
       FROM clinical.appointments a
       LEFT JOIN clinical.patients p ON a.patient_id = p.id
       LEFT JOIN clinical.doctors d ON a.doctor_id = d.id
       LEFT JOIN clinical.appointment_queue q ON a.id = q.appointment_id
       WHERE a.id = $1`,
      [id]
    );
    
    if (result.rows.length === 0) {
      throw new NotFoundError('Appointment');
    }
    
    res.json({
      success: true,
      data: result.rows[0],
    });
  } catch (error) {
    if (error instanceof NotFoundError) {
      throw error;
    }
    throw handleDatabaseError(error);
  }
}));

/**
 * Get appointments by patient
 */
app.get('/patient/:patientId', asyncHandler(async (req: Request, res: Response) => {
  const { patientId } = req.params;
  const { status, startDate, endDate, page = 1, limit = 20 } = req.query;
  
  const offset = (Number(page) - 1) * Number(limit);
  
  let queryText = `
    SELECT 
      a.id, a.appointment_number, a.appointment_date, a.appointment_time,
      a.appointment_type, a.reason, a.status,
      d.first_name as doctor_first_name, d.last_name as doctor_last_name,
      d.specialization as doctor_specialization
    FROM clinical.appointments a
    LEFT JOIN clinical.doctors d ON a.doctor_id = d.id
    WHERE a.patient_id = $1
  `;
  
  const params: any[] = [patientId];
  let paramCount = 2;
  
  if (status) {
    queryText += ` AND a.status = $${paramCount}`;
    params.push(status);
    paramCount++;
  }
  
  if (startDate && endDate) {
    queryText += ` AND a.appointment_date BETWEEN $${paramCount} AND $${paramCount + 1}`;
    params.push(startDate, endDate);
    paramCount += 2;
  }
  
  queryText += ` ORDER BY a.appointment_date DESC, a.appointment_time DESC LIMIT $${paramCount} OFFSET $${paramCount + 1}`;
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
 * Get appointments by doctor
 */
app.get('/doctor/:doctorId', asyncHandler(async (req: Request, res: Response) => {
  const { doctorId } = req.params;
  const { date, status, page = 1, limit = 20 } = req.query;
  
  const offset = (Number(page) - 1) * Number(limit);
  
  let queryText = `
    SELECT 
      a.id, a.appointment_number, a.appointment_date, a.appointment_time,
      a.appointment_type, a.reason, a.status,
      p.first_name as patient_first_name, p.last_name as patient_last_name,
      p.phone as patient_phone, p.mrn as patient_mrn,
      q.queue_position, q.status as queue_status
    FROM clinical.appointments a
    LEFT JOIN clinical.patients p ON a.patient_id = p.id
    LEFT JOIN clinical.appointment_queue q ON a.id = q.appointment_id
    WHERE a.doctor_id = $1
  `;
  
  const params: any[] = [doctorId];
  let paramCount = 2;
  
  if (date) {
    queryText += ` AND a.appointment_date = $${paramCount}`;
    params.push(date);
    paramCount++;
  }
  
  if (status) {
    queryText += ` AND a.status = $${paramCount}`;
    params.push(status);
    paramCount++;
  }
  
  queryText += ` ORDER BY a.appointment_date, a.appointment_time LIMIT $${paramCount} OFFSET $${paramCount + 1}`;
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
 * Update appointment status
 */
app.put('/:id/status', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const { status, cancellationReason } = req.body;
  
  if (!status) {
    throw new ValidationError('Status is required');
  }
  
  const validStatuses = ['scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show'];
  if (!validStatuses.includes(status)) {
    throw new ValidationError(`Invalid status. Must be one of: ${validStatuses.join(', ')}`);
  }
  
  try {
    const result = await transaction(async (client) => {
      // Update appointment
      const appointment = await client.query(
        `UPDATE clinical.appointments
         SET status = $1, 
             cancellation_reason = $2,
             updated_at = NOW()
         WHERE id = $3
         RETURNING id, appointment_number, status, updated_at`,
        [status, cancellationReason || null, id]
      );
      
      if (appointment.rows.length === 0) {
        throw new NotFoundError('Appointment');
      }
      
      // Update queue status
      if (status === 'in_progress') {
        await client.query(
          `UPDATE clinical.appointment_queue
           SET status = 'in_consultation', called_at = NOW()
           WHERE appointment_id = $1`,
          [id]
        );
      } else if (status === 'completed' || status === 'cancelled' || status === 'no_show') {
        await client.query(
          `UPDATE clinical.appointment_queue
           SET status = 'completed', completed_at = NOW()
           WHERE appointment_id = $1`,
          [id]
        );
      }
      
      return appointment.rows[0];
    });
    
    res.json({
      success: true,
      message: 'Appointment status updated successfully',
      data: result,
    });
  } catch (error) {
    if (error instanceof NotFoundError) {
      throw error;
    }
    throw handleDatabaseError(error);
  }
}));

/**
 * Reschedule appointment
 */
app.put('/:id/reschedule', asyncHandler(async (req: Request, res: Response) => {
  const { id } = req.params;
  const { appointmentDate, appointmentTime } = req.body;
  
  if (!appointmentDate || !appointmentTime) {
    throw new ValidationError('New appointment date and time are required');
  }
  
  // Validate date is not in the past
  const newDateTime = new Date(`${appointmentDate}T${appointmentTime}`);
  if (newDateTime < new Date()) {
    throw new ValidationError('Cannot reschedule to a past date/time');
  }
  
  try {
    // Get current appointment
    const current = await query(
      `SELECT doctor_id FROM clinical.appointments WHERE id = $1`,
      [id]
    );
    
    if (current.rows.length === 0) {
      throw new NotFoundError('Appointment');
    }
    
    // Check new time availability
    const availability = await checkDoctorAvailability(
      current.rows[0].doctor_id,
      appointmentDate,
      appointmentTime
    );
    
    if (!availability.available) {
      throw new ConflictError(availability.reason || 'New time slot not available');
    }
    
    // Update appointment
    const result = await query(
      `UPDATE clinical.appointments
       SET appointment_date = $1,
           appointment_time = $2,
           updated_at = NOW()
       WHERE id = $3
       RETURNING id, appointment_number, appointment_date, appointment_time, updated_at`,
      [appointmentDate, appointmentTime, id]
    );
    
    res.json({
      success: true,
      message: 'Appointment rescheduled successfully',
      data: result.rows[0],
    });
  } catch (error) {
    if (error instanceof NotFoundError || error instanceof ConflictError) {
      throw error;
    }
    throw handleDatabaseError(error);
  }
}));

/**
 * Get available time slots
 */
app.get('/availability/:doctorId', asyncHandler(async (req: Request, res: Response) => {
  const { doctorId } = req.params;
  const { date } = req.query;
  
  if (!date) {
    throw new ValidationError('Date is required');
  }
  
  try {
    const dayOfWeek = new Date(date as string).toLocaleDateString('en-US', { weekday: 'long' }).toLowerCase();
    
    // Get doctor's schedule
    const schedule = await query(
      `SELECT start_time, end_time, slot_duration, max_patients_per_slot
       FROM clinical.doctor_schedules
       WHERE doctor_id = $1 AND day_of_week = $2 AND is_available = true AND is_active = true`,
      [doctorId, dayOfWeek]
    );
    
    if (schedule.rows.length === 0) {
      return res.json({
        success: true,
        data: {
          available: false,
          reason: 'Doctor not available on this day',
          slots: [],
        },
      });
    }
    
    // Check for leave
    const leave = await query(
      `SELECT id FROM clinical.doctor_leaves
       WHERE doctor_id = $1 AND leave_date = $2 AND status = 'approved'`,
      [doctorId, date]
    );
    
    if (leave.rows.length > 0) {
      return res.json({
        success: true,
        data: {
          available: false,
          reason: 'Doctor on leave',
          slots: [],
        },
      });
    }
    
    const { start_time, end_time, slot_duration, max_patients_per_slot } = schedule.rows[0];
    
    // Generate time slots
    const slots = [];
    let currentTime = start_time;
    
    while (currentTime < end_time) {
      // Check existing appointments
      const booked = await query(
        `SELECT COUNT(*) as count
         FROM clinical.appointments
         WHERE doctor_id = $1 
         AND appointment_date = $2 
         AND appointment_time = $3
         AND status NOT IN ('cancelled', 'no_show')`,
        [doctorId, date, currentTime]
      );
      
      const bookedCount = parseInt(booked.rows[0].count);
      const available = bookedCount < max_patients_per_slot;
      
      slots.push({
        time: currentTime,
        available,
        bookedCount,
        maxCapacity: max_patients_per_slot,
      });
      
      // Add slot duration to current time
      const [hours, minutes] = currentTime.split(':').map(Number);
      const totalMinutes = hours * 60 + minutes + slot_duration;
      const newHours = Math.floor(totalMinutes / 60);
      const newMinutes = totalMinutes % 60;
      currentTime = `${String(newHours).padStart(2, '0')}:${String(newMinutes).padStart(2, '0')}:00`;
    }
    
    res.json({
      success: true,
      data: {
        available: true,
        date,
        slots,
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
const PORT = process.env.APPOINTMENT_SERVICE_PORT || 3004;

async function startServer() {
  try {
    await initializeDatabase();
    
    app.listen(PORT, () => {
      console.log(`📅 Appointment Service running on port ${PORT}`);
      console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
    });
  } catch (error) {
    console.error('Failed to start appointment service:', error);
    process.exit(1);
  }
}

startServer();

export default app;
