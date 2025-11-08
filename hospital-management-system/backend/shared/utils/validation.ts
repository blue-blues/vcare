/**
 * Validation Utilities
 * CRITICAL: All input validation to prevent injection attacks and data corruption
 */

import Joi from 'joi';

/**
 * Common validation schemas
 */
export const commonSchemas = {
  // UUID validation
  uuid: Joi.string().uuid({ version: 'uuidv4' }).required(),
  
  // Email validation
  email: Joi.string()
    .email({ minDomainSegments: 2, tlds: { allow: true } })
    .max(255)
    .lowercase()
    .trim()
    .required(),
  
  // Phone validation (international format)
  phone: Joi.string()
    .pattern(/^\+?[1-9]\d{1,14}$/)
    .min(10)
    .max(15)
    .required(),
  
  // Password validation (strong password)
  password: Joi.string()
    .min(8)
    .max(128)
    .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/)
    .required()
    .messages({
      'string.pattern.base': 'Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character',
    }),
  
  // Date validation
  date: Joi.date().iso().required(),
  
  // Date of birth (must be in the past)
  dateOfBirth: Joi.date()
    .max('now')
    .min('1900-01-01')
    .required(),
  
  // Positive integer
  positiveInteger: Joi.number().integer().positive().required(),
  
  // Non-negative integer
  nonNegativeInteger: Joi.number().integer().min(0).required(),
  
  // Positive decimal
  positiveDecimal: Joi.number().positive().precision(2).required(),
  
  // Non-negative decimal
  nonNegativeDecimal: Joi.number().min(0).precision(2).required(),
  
  // Pagination
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(100).default(20),
  
  // Search query
  searchQuery: Joi.string().min(1).max(255).trim(),
};

/**
 * Medical validation schemas
 */
export const medicalSchemas = {
  // Blood pressure
  bloodPressureSystolic: Joi.number().integer().min(40).max(300).required(),
  bloodPressureDiastolic: Joi.number().integer().min(20).max(200).required(),
  
  // Heart rate
  heartRate: Joi.number().integer().min(20).max(300).required(),
  
  // Temperature (Celsius)
  temperature: Joi.number().min(32.0).max(45.0).precision(1).required(),
  
  // Respiratory rate
  respiratoryRate: Joi.number().integer().min(5).max(60).required(),
  
  // Oxygen saturation
  oxygenSaturation: Joi.number().min(50).max(100).precision(2).required(),
  
  // Weight (kg)
  weight: Joi.number().min(0.5).max(500).precision(2).required(),
  
  // Height (cm)
  height: Joi.number().min(20).max(300).precision(1).required(),
  
  // BMI
  bmi: Joi.number().min(10).max(100).precision(2),
  
  // Glasgow Coma Scale
  glasgowComaScale: Joi.number().integer().min(3).max(15).required(),
  
  // Pain scale
  painScale: Joi.number().integer().min(0).max(10).required(),
  
  // ICD code
  icdCode: Joi.string().pattern(/^[A-Z]\d{2}(\.\d{1,2})?$/).required(),
  
  // CPT code
  cptCode: Joi.string().pattern(/^\d{5}$/).required(),
};

/**
 * User validation schemas
 */
export const userSchemas = {
  // Registration
  register: Joi.object({
    username: Joi.string().alphanum().min(3).max(50).required(),
    email: commonSchemas.email,
    password: commonSchemas.password,
    userType: Joi.string().valid('patient', 'doctor', 'nurse', 'admin', 'staff').required(),
    firstName: Joi.string().min(1).max(100).trim().required(),
    lastName: Joi.string().min(1).max(100).trim().required(),
    phone: commonSchemas.phone,
    dateOfBirth: commonSchemas.dateOfBirth,
    gender: Joi.string().valid('male', 'female', 'other').required(),
  }),
  
  // Login
  login: Joi.object({
    username: Joi.string().required(),
    password: Joi.string().required(),
    mfaToken: Joi.string().length(6).pattern(/^\d+$/),
  }),
  
  // Update profile
  updateProfile: Joi.object({
    firstName: Joi.string().min(1).max(100).trim(),
    lastName: Joi.string().min(1).max(100).trim(),
    phone: commonSchemas.phone.optional(),
    email: commonSchemas.email.optional(),
    dateOfBirth: commonSchemas.dateOfBirth.optional(),
    gender: Joi.string().valid('male', 'female', 'other'),
  }).min(1),
  
  // Change password
  changePassword: Joi.object({
    currentPassword: Joi.string().required(),
    newPassword: commonSchemas.password,
    confirmPassword: Joi.string().valid(Joi.ref('newPassword')).required()
      .messages({ 'any.only': 'Passwords do not match' }),
  }),
};

/**
 * Patient validation schemas
 */
export const patientSchemas = {
  // Create patient
  create: Joi.object({
    firstName: Joi.string().min(1).max(100).trim().required(),
    lastName: Joi.string().min(1).max(100).trim().required(),
    dateOfBirth: commonSchemas.dateOfBirth,
    gender: Joi.string().valid('male', 'female', 'other').required(),
    bloodGroup: Joi.string().valid('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'),
    phone: commonSchemas.phone,
    email: commonSchemas.email.optional(),
    emergencyContactName: Joi.string().min(1).max(255).trim().required(),
    emergencyContactPhone: commonSchemas.phone,
    emergencyContactRelationship: Joi.string().min(1).max(100).trim().required(),
    address: Joi.object({
      line1: Joi.string().min(1).max(255).trim().required(),
      line2: Joi.string().max(255).trim().allow(''),
      city: Joi.string().min(1).max(100).trim().required(),
      state: Joi.string().min(1).max(100).trim().required(),
      country: Joi.string().min(1).max(100).trim().required(),
      postalCode: Joi.string().min(1).max(20).trim().required(),
    }).required(),
  }),
  
  // Add allergy
  addAllergy: Joi.object({
    allergen: Joi.string().min(1).max(255).trim().required(),
    allergyType: Joi.string().valid('drug', 'food', 'environmental', 'other').required(),
    severity: Joi.string().valid('mild', 'moderate', 'severe', 'life_threatening').required(),
    reaction: Joi.string().min(1).max(500).trim().required(),
    onsetDate: commonSchemas.date.optional(),
    notes: Joi.string().max(1000).trim().allow(''),
  }),
};

/**
 * Appointment validation schemas
 */
export const appointmentSchemas = {
  // Create appointment
  create: Joi.object({
    patientId: commonSchemas.uuid,
    doctorId: commonSchemas.uuid,
    appointmentDate: Joi.date().min('now').required(),
    appointmentTime: Joi.string().pattern(/^([01]\d|2[0-3]):([0-5]\d)$/).required(),
    duration: Joi.number().integer().min(15).max(240).default(30),
    appointmentType: Joi.string().valid('consultation', 'follow_up', 'emergency', 'routine_checkup', 'procedure').required(),
    reason: Joi.string().min(1).max(500).trim().required(),
    notes: Joi.string().max(1000).trim().allow(''),
  }),
  
  // Update appointment
  update: Joi.object({
    appointmentDate: Joi.date().min('now'),
    appointmentTime: Joi.string().pattern(/^([01]\d|2[0-3]):([0-5]\d)$/),
    duration: Joi.number().integer().min(15).max(240),
    status: Joi.string().valid('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show'),
    notes: Joi.string().max(1000).trim().allow(''),
  }).min(1),
};

/**
 * Prescription validation schemas
 */
export const prescriptionSchemas = {
  // Create prescription
  create: Joi.object({
    patientId: commonSchemas.uuid,
    consultationId: commonSchemas.uuid,
    medications: Joi.array().items(
      Joi.object({
        medicineId: commonSchemas.uuid,
        medicineName: Joi.string().min(1).max(255).trim().required(),
        dosage: Joi.string().min(1).max(100).trim().required(),
        frequency: Joi.string().min(1).max(100).trim().required(),
        duration: Joi.string().min(1).max(100).trim().required(),
        route: Joi.string().valid('oral', 'injection', 'topical', 'inhalation', 'sublingual', 'rectal', 'other').required(),
        instructions: Joi.string().max(500).trim().allow(''),
        quantity: commonSchemas.positiveInteger,
      })
    ).min(1).required(),
    notes: Joi.string().max(1000).trim().allow(''),
  }),
};

/**
 * Lab order validation schemas
 */
export const labOrderSchemas = {
  // Create lab order
  create: Joi.object({
    patientId: commonSchemas.uuid,
    doctorId: commonSchemas.uuid,
    consultationId: commonSchemas.uuid.optional(),
    tests: Joi.array().items(commonSchemas.uuid).min(1).required(),
    priority: Joi.string().valid('routine', 'urgent', 'stat').default('routine'),
    clinicalNotes: Joi.string().max(1000).trim().allow(''),
    provisionalDiagnosis: Joi.string().max(500).trim().allow(''),
  }),
};

/**
 * Validate request body against schema
 */
export function validateRequest(schema: Joi.ObjectSchema, data: any): {
  error: string | null;
  value: any;
} {
  const { error, value } = schema.validate(data, {
    abortEarly: false,
    stripUnknown: true,
  });
  
  if (error) {
    const errorMessage = error.details
      .map((detail) => detail.message)
      .join(', ');
    return { error: errorMessage, value: null };
  }
  
  return { error: null, value };
}

/**
 * Sanitize string input (prevent XSS)
 */
export function sanitizeString(input: string): string {
  if (!input) return '';
  
  return input
    .trim()
    .replace(/[<>]/g, '') // Remove < and >
    .replace(/javascript:/gi, '') // Remove javascript: protocol
    .replace(/on\w+=/gi, ''); // Remove event handlers
}

/**
 * Validate SQL injection patterns
 */
export function hasSQLInjection(input: string): boolean {
  const sqlPatterns = [
    /(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|EXECUTE)\b)/gi,
    /(--|;|\/\*|\*\/|xp_|sp_)/gi,
    /(\bOR\b.*=.*|1=1|'=')/gi,
  ];
  
  return sqlPatterns.some((pattern) => pattern.test(input));
}

/**
 * Validate file upload
 */
export function validateFileUpload(file: any, allowedTypes: string[], maxSize: number): {
  valid: boolean;
  error?: string;
} {
  if (!file) {
    return { valid: false, error: 'No file provided' };
  }
  
  // Check file type
  if (!allowedTypes.includes(file.mimetype)) {
    return { valid: false, error: `File type not allowed. Allowed types: ${allowedTypes.join(', ')}` };
  }
  
  // Check file size
  if (file.size > maxSize) {
    return { valid: false, error: `File size exceeds maximum allowed size of ${maxSize / 1024 / 1024}MB` };
  }
  
  return { valid: true };
}

/**
 * Validate date range
 */
export function validateDateRange(startDate: Date, endDate: Date): boolean {
  return startDate <= endDate;
}

/**
 * Validate age
 */
export function calculateAge(dateOfBirth: Date): number {
  const today = new Date();
  let age = today.getFullYear() - dateOfBirth.getFullYear();
  const monthDiff = today.getMonth() - dateOfBirth.getMonth();
  
  if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < dateOfBirth.getDate())) {
    age--;
  }
  
  return age;
}

/**
 * Validate BMI calculation
 */
export function calculateBMI(weight: number, height: number): number {
  // weight in kg, height in cm
  const heightInMeters = height / 100;
  return parseFloat((weight / (heightInMeters * heightInMeters)).toFixed(2));
}

/**
 * Validate vital signs are within safe ranges
 */
export function validateVitalSigns(vitals: {
  bloodPressureSystolic?: number;
  bloodPressureDiastolic?: number;
  heartRate?: number;
  temperature?: number;
  respiratoryRate?: number;
  oxygenSaturation?: number;
}): {
  valid: boolean;
  criticalValues: string[];
} {
  const criticalValues: string[] = [];
  
  // Blood pressure
  if (vitals.bloodPressureSystolic) {
    if (vitals.bloodPressureSystolic < 90 || vitals.bloodPressureSystolic > 180) {
      criticalValues.push(`Blood Pressure: ${vitals.bloodPressureSystolic}/${vitals.bloodPressureDiastolic}`);
    }
  }
  
  // Heart rate
  if (vitals.heartRate) {
    if (vitals.heartRate < 40 || vitals.heartRate > 140) {
      criticalValues.push(`Heart Rate: ${vitals.heartRate} bpm`);
    }
  }
  
  // Temperature
  if (vitals.temperature) {
    if (vitals.temperature < 35.0 || vitals.temperature > 39.5) {
      criticalValues.push(`Temperature: ${vitals.temperature}°C`);
    }
  }
  
  // Oxygen saturation
  if (vitals.oxygenSaturation) {
    if (vitals.oxygenSaturation < 90) {
      criticalValues.push(`SpO2: ${vitals.oxygenSaturation}%`);
    }
  }
  
  return {
    valid: criticalValues.length === 0,
    criticalValues,
  };
}
