# Implementation Roadmap - Step-by-Step Building Guide

## Phase 1: Foundation (Months 1-3)

### Month 1: Project Setup & Core Infrastructure

#### Week 1-2: Development Environment Setup
```bash
# 1. Initialize project structure
mkdir hospital-management-system
cd hospital-management-system

# 2. Create main directories
mkdir -p backend/{services,shared,config}
mkdir -p frontend/{patient-portal,doctor-portal,admin-portal}
mkdir -p ai-services/{diagnosis,prediction,nlp}
mkdir -p infrastructure/{docker,kubernetes,terraform}
mkdir -p database/{migrations,seeds}
mkdir -p docs tests

# 3. Initialize Git repository
git init
echo "# Hospital Management System" > README.md
git add .
git commit -m "Initial project structure"

# 4. Setup development tools
npm init -y
npm install -D @types/node typescript eslint prettier
npm install -D jest @types/jest ts-jest
npm install -D husky lint-staged

# 5. Configure TypeScript
cat > tsconfig.json << EOF
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  }
}
EOF
```

#### Week 3-4: Database Setup
```sql
-- 1. Setup PostgreSQL
CREATE DATABASE hospital_management;
CREATE USER hms_admin WITH ENCRYPTED PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE hospital_management TO hms_admin;

-- 2. Create base schemas
CREATE SCHEMA core;
CREATE SCHEMA clinical;
CREATE SCHEMA billing;
CREATE SCHEMA inventory;

-- 3. Setup extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
```

```javascript
// 4. Setup database migrations (using Knex.js)
// knexfile.js
module.exports = {
  development: {
    client: 'postgresql',
    connection: {
      database: 'hospital_management',
      user: 'hms_admin',
      password: 'secure_password'
    },
    migrations: {
      directory: './database/migrations'
    },
    seeds: {
      directory: './database/seeds'
    }
  }
};

// 5. Create first migration
// database/migrations/001_create_users_table.js
exports.up = function(knex) {
  return knex.schema.createTable('users', table => {
    table.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
    table.string('username', 50).unique().notNullable();
    table.string('email', 255).unique().notNullable();
    table.string('password_hash', 255).notNullable();
    table.enum('user_type', ['patient', 'doctor', 'nurse', 'admin', 'staff']).notNullable();
    table.boolean('is_active').defaultTo(true);
    table.timestamps(true, true);
  });
};
```

### Month 2: Core Services Development

#### Week 5-6: Authentication Service
```typescript
// backend/services/auth-service/src/index.ts
import express from 'express';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';
import { Pool } from 'pg';

const app = express();
app.use(express.json());

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

// User registration
app.post('/api/v1/auth/register', async (req, res) => {
  try {
    const { username, email, password, userType } = req.body;
    
    // Validate input
    if (!username || !email || !password) {
      return res.status(400).json({ 
        success: false, 
        error: 'Missing required fields' 
      });
    }
    
    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);
    
    // Insert user
    const result = await pool.query(
      `INSERT INTO users (username, email, password_hash, user_type) 
       VALUES ($1, $2, $3, $4) 
       RETURNING id, username, email, user_type`,
      [username, email, passwordHash, userType]
    );
    
    // Generate JWT
    const token = jwt.sign(
      { 
        userId: result.rows[0].id, 
        userType: result.rows[0].user_type 
      },
      process.env.JWT_SECRET,
      { expiresIn: '24h' }
    );
    
    res.status(201).json({
      success: true,
      data: {
        user: result.rows[0],
        token
      }
    });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Internal server error' 
    });
  }
});

// User login
app.post('/api/v1/auth/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    
    // Get user
    const result = await pool.query(
      'SELECT * FROM users WHERE username = $1 OR email = $1',
      [username]
    );
    
    if (result.rows.length === 0) {
      return res.status(401).json({ 
        success: false, 
        error: 'Invalid credentials' 
      });
    }
    
    const user = result.rows[0];
    
    // Verify password
    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      return res.status(401).json({ 
        success: false, 
        error: 'Invalid credentials' 
      });
    }
    
    // Generate JWT
    const token = jwt.sign(
      { 
        userId: user.id, 
        userType: user.user_type 
      },
      process.env.JWT_SECRET,
      { expiresIn: '24h' }
    );
    
    res.json({
      success: true,
      data: {
        token,
        user: {
          id: user.id,
          username: user.username,
          email: user.email,
          userType: user.user_type
        }
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Internal server error' 
    });
  }
});

// Middleware for protected routes
export const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  
  if (!token) {
    return res.status(401).json({ 
      success: false, 
      error: 'Access token required' 
    });
  }
  
  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ 
        success: false, 
        error: 'Invalid token' 
      });
    }
    req.user = user;
    next();
  });
};

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`Auth service running on port ${PORT}`);
});
```

#### Week 7-8: Patient Service
```typescript
// backend/services/patient-service/src/index.ts
import express from 'express';
import { Pool } from 'pg';
import { authenticateToken } from '../../shared/middleware/auth';

const app = express();
app.use(express.json());

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

// Create patient profile
app.post('/api/v1/patients', authenticateToken, async (req, res) => {
  try {
    const {
      firstName,
      lastName,
      dateOfBirth,
      gender,
      bloodGroup,
      phone,
      email,
      address,
      emergencyContact
    } = req.body;
    
    // Generate patient number
    const patientNumber = await generatePatientNumber();
    
    // Begin transaction
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      
      // Insert patient
      const patientResult = await client.query(
        `INSERT INTO patients (
          user_id, patient_number, first_name, last_name,
          date_of_birth, gender, blood_group, phone_primary, email,
          address_line1, city, state, postal_code,
          emergency_contact_name, emergency_contact_phone
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
        RETURNING *`,
        [
          req.user.userId, patientNumber, firstName, lastName,
          dateOfBirth, gender, bloodGroup, phone, email,
          address.line1, address.city, address.state, address.postalCode,
          emergencyContact.name, emergencyContact.phone
        ]
      );
      
      await client.query('COMMIT');
      
      res.status(201).json({
        success: true,
        data: {
          patient: patientResult.rows[0]
        }
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('Error creating patient:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to create patient profile' 
    });
  }
});

// Get patient details
app.get('/api/v1/patients/:id', authenticateToken, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT p.*, 
        COUNT(DISTINCT a.id) as total_appointments,
        COUNT(DISTINCT c.id) as total_consultations
       FROM patients p
       LEFT JOIN appointments a ON p.id = a.patient_id
       LEFT JOIN consultations c ON p.id = c.patient_id
       WHERE p.id = $1
       GROUP BY p.id`,
      [req.params.id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ 
        success: false, 
        error: 'Patient not found' 
      });
    }
    
    res.json({
      success: true,
      data: {
        patient: result.rows[0]
      }
    });
  } catch (error) {
    console.error('Error fetching patient:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to fetch patient details' 
    });
  }
});

async function generatePatientNumber() {
  const year = new Date().getFullYear();
  const result = await pool.query(
    `SELECT COUNT(*) as count FROM patients 
     WHERE patient_number LIKE $1`,
    [`PAT-${year}-%`]
  );
  const count = parseInt(result.rows[0].count) + 1;
  return `PAT-${year}-${String(count).padStart(5, '0')}`;
}

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => {
  console.log(`Patient service running on port ${PORT}`);
});
```

### Month 3: Frontend Foundation

#### Week 9-10: React Setup for Patient Portal
```typescript
// frontend/patient-portal/src/App.tsx
import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import { AuthProvider } from './contexts/AuthContext';
import { Layout } from './components/Layout';
import { Dashboard } from './pages/Dashboard';
import { Appointments } from './pages/Appointments';
import { MedicalRecords } from './pages/MedicalRecords';
import { Login } from './pages/Login';
import { ProtectedRoute } from './components/ProtectedRoute';

const theme = createTheme({
  palette: {
    primary: {
      main: '#2196f3',
    },
    secondary: {
      main: '#f50057',
    },
  },
});

function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <AuthProvider>
        <Router>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route path="/" element={<ProtectedRoute><Layout /></ProtectedRoute>}>
              <Route index element={<Dashboard />} />
              <Route path="appointments" element={<Appointments />} />
              <Route path="medical-records" element={<MedicalRecords />} />
            </Route>
          </Routes>
        </Router>
      </AuthProvider>
    </ThemeProvider>
  );
}

export default App;
```

```typescript
// frontend/patient-portal/src/contexts/AuthContext.tsx
import React, { createContext, useContext, useState, useEffect } from 'react';
import axios from 'axios';

interface User {
  id: string;
  username: string;
  email: string;
  userType: string;
}

interface AuthContextType {
  user: User | null;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
  isLoading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
};

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const token = localStorage.getItem('token');
    if (token) {
      // Verify token and get user info
      verifyToken(token);
    } else {
      setIsLoading(false);
    }
  }, []);

  const verifyToken = async (token: string) => {
    try {
      axios.defaults.headers.common['Authorization'] = `Bearer ${token}`;
      const response = await axios.get('/api/v1/auth/verify');
      setUser(response.data.user);
    } catch (error) {
      localStorage.removeItem('token');
      delete axios.defaults.headers.common['Authorization'];
    } finally {
      setIsLoading(false);
    }
  };

  const login = async (username: string, password: string) => {
    const response = await axios.post('/api/v1/auth/login', {
      username,
      password
    });
    
    const { token, user } = response.data.data;
    localStorage.setItem('token', token);
    axios.defaults.headers.common['Authorization'] = `Bearer ${token}`;
    setUser(user);
  };

  const logout = () => {
    localStorage.removeItem('token');
    delete axios.defaults.headers.common['Authorization'];
    setUser(null);
  };

  return (
    <AuthContext.Provider value={{ user, login, logout, isLoading }}>
      {children}
    </AuthContext.Provider>
  );
};
```

#### Week 11-12: API Gateway Setup
```typescript
// backend/api-gateway/src/index.ts
import express from 'express';
import httpProxy from 'http-proxy-middleware';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import cors from 'cors';
import morgan from 'morgan';

const app = express();

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
  credentials: true
}));

// Logging
app.use(morgan('combined'));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use('/api/', limiter);

// Service routes
const services = {
  '/api/v1/auth': 'http://auth-service:3001',
  '/api/v1/patients': 'http://patient-service:3002',
  '/api/v1/appointments': 'http://appointment-service:3003',
  '/api/v1/consultations': 'http://consultation-service:3004',
  '/api/v1/lab': 'http://lab-service:3005',
  '/api/v1/pharmacy': 'http://pharmacy-service:3006',
  '/api/v1/billing': 'http://billing-service:3007',
  '/api/v1/ai': 'http://ai-service:3008'
};

// Setup proxies
Object.keys(services).forEach(path => {
  app.use(path, httpProxy.createProxyMiddleware({
    target: services[path],
    changeOrigin: true,
    onError: (err, req, res) => {
      console.error(`Error proxying to ${services[path]}:`, err);
      res.status(503).json({
        success: false,
        error: 'Service temporarily unavailable'
      });
    }
  }));
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`API Gateway running on port ${PORT}`);
});
```

## Phase 2: Clinical Core (Months 4-6)

### Month 4: Appointment & Consultation System

#### Week 13-14: Appointment Service
```typescript
// backend/services/appointment-service/src/index.ts
import express from 'express';
import { Pool } from 'pg';
import { authenticateToken } from '../../shared/middleware/auth';
import { sendNotification } from '../../shared/services/notification';

const app = express();
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// Check availability
app.get('/api/v1/appointments/availability', authenticateToken, async (req, res) => {
  try {
    const { doctorId, date } = req.query;
    
    // Get doctor's schedule
    const scheduleResult = await pool.query(
      `SELECT * FROM doctor_schedules 
       WHERE doctor_id = $1 
       AND day_of_week = EXTRACT(DOW FROM $2::date)
       AND is_active = true`,
      [doctorId, date]
    );
    
    if (scheduleResult.rows.length === 0) {
      return res.json({ success: true, data: { available_slots: [] } });
    }
    
    const schedule = scheduleResult.rows[0];
    
    // Get existing appointments
    const appointmentsResult = await pool.query(
      `SELECT appointment_time, duration_minutes 
       FROM appointments 
       WHERE doctor_id = $1 
       AND appointment_date = $2 
       AND status NOT IN ('cancelled', 'no-show')`,
      [doctorId, date]
    );
    
    // Generate available slots
    const slots = generateTimeSlots(
      schedule.start_time,
      schedule.end_time,
      30, // 30-minute slots
      appointmentsResult.rows
    );
    
    res.json({
      success: true,
      data: { available_slots: slots }
    });
  } catch (error) {
    console.error('Error checking availability:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to check availability' 
    });
  }
});

// Book appointment
app.post('/api/v1/appointments', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    const {
      patientId,
      doctorId,
      appointmentDate,
      appointmentTime,
      appointmentType,
      reasonForVisit,
      symptoms
    } = req.body;
    
    // Check if slot is still available
    const existingAppointment = await client.query(
      `SELECT id FROM appointments 
       WHERE doctor_id = $1 
       AND appointment_date = $2 
       AND appointment_time = $3 
       AND status NOT IN ('cancelled', 'no-show')`,
      [doctorId, appointmentDate, appointmentTime]
    );
    
    if (existingAppointment.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({ 
        success: false, 
        error: 'Slot no longer available' 
      });
    }
    
    // Generate appointment number
    const appointmentNumber = await generateAppointmentNumber();
    
    // Create appointment
    const result = await client.query(
      `INSERT INTO appointments (
        appointment_number, patient_id, doctor_id,
        appointment_date, appointment_time, appointment_type,
        reason_for_visit, symptoms, status, created_by
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'scheduled', $9)
      RETURNING *`,
      [
        appointmentNumber, patientId, doctorId,
        appointmentDate, appointmentTime, appointmentType,
        reasonForVisit, symptoms, req.user.userId
      ]
    );
    
    await client.query('COMMIT');
    
    // Send confirmation notification
    await sendNotification({
      type: 'appointment_confirmation',
      recipientId: patientId,
      data: result.rows[0]
    });
    
    res.status(201).json({
      success: true,
      data: { appointment: result.rows[0] }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error booking appointment:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to book appointment' 
    });
  } finally {
    client.release();
  }
});

function generateTimeSlots(startTime, endTime, duration, bookedSlots) {
  const slots = [];
  let current = new Date(`2000-01-01 ${startTime}`);
  const end = new Date(`2000-01-01 ${endTime}`);
  
  while (current < end) {
    const timeStr = current.toTimeString().slice(0, 5);
    const isBooked = bookedSlots.some(slot => 
      slot.appointment_time === timeStr
    );
    
    if (!isBooked) {
      slots.push({
        time: timeStr,
        duration_minutes: duration
      });
    }
    
    current.setMinutes(current.getMinutes() + duration);
  }
  
  return slots;
}

async function generateAppointmentNumber() {
  const year = new Date().getFullYear();
  const result = await pool.query(
    `SELECT COUNT(*) as count FROM appointments 
     WHERE appointment_number LIKE $1`,
    [`APT-${year}-%`]
  );
  const count = parseInt(result.rows[0].count) + 1;
  return `APT-${year}-${String(count).padStart(5, '0')}`;
}

const PORT = process.env.PORT || 3003;
app.listen(PORT, () => {
  console.log(`Appointment service running on port ${PORT}`);
});
```

### Month 5: Laboratory & Pharmacy Services

#### Week 17-18: Laboratory Service
```typescript
// backend/services/lab-service/src/index.ts
import express from 'express';
import { Pool } from 'pg';
import { authenticateToken } from '../../shared/middleware/auth';
import { generateBarcode } from '../../shared/utils/barcode';
import { sendCriticalAlert } from '../../shared/services/alert';

const app = express();
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// Order lab tests
app.post('/api/v1/lab/orders', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    const {
      patientId,
      doctorId,
      consultationId,
      tests,
      priority,
      clinicalNotes
    } = req.body;
    
    // Generate order number
    const orderNumber = await generateLabOrderNumber();
    
    // Create lab order
    const orderResult = await client.query(
      `INSERT INTO lab_orders (
        order_number, patient_id, doctor_id, consultation_id,
        priority, clinical_notes, status
      ) VALUES ($1, $2, $3, $4, $5, $6, 'ordered')
      RETURNING *`,
      [orderNumber, patientId, doctorId, consultationId, priority, clinicalNotes]
    );
    
    const orderId = orderResult.rows[0].id;
    
    // Create order items with barcodes
    const orderItems = [];
    for (const test of tests) {
      const barcode = generateBarcode();
      const itemResult = await client.query(
        `INSERT INTO lab_order_items (
          order_id, test_id, sample_id, status
        ) VALUES ($1, $2, $3, 'pending')
        RETURNING *`,
        [orderId, test.testId, barcode]
      );
      orderItems.push(itemResult.rows[0]);
    }
    
    await client.query('COMMIT');
    
    res.status(201).json({
      success: true,
      data: {
        order: orderResult.rows[0],
        items: orderItems
      }
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error creating lab order:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to create lab order' 
    });
  } finally {
    client.release();
  }
});

// Submit lab results
app.post('/api/v1/lab/results', authenticateToken, async (req, res) => {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    
    const {
      orderItemId,
      resultValue,
      resultUnit,
      performedBy
    } = req.body;
    
    // Get test details and reference ranges
    const testResult = await client.query(
      `SELECT lt.*, loi.order_id, lo.patient_id 
       FROM lab_order_items loi
       JOIN lab_orders lo ON loi.order_id = lo.id
       JOIN lab_tests lt ON loi.test_id = lt.id
       WHERE loi.id = $1`,
      [orderItemId]
    );
    
    if (testResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ 
        success: false, 
        error: 'Lab order item not found' 
      });
    }
    
    const test = testResult.rows[0];
    const referenceRanges = test.reference_ranges;
    
    // Check if result is abnormal
    const { isAbnormal, abnormalityType } = checkAbnormalResult(
      resultValue,
      referenceRanges
    );
    
    // Update lab order item with results
    await client.query(
      `UPDATE lab_order_items 
       SET result_value = $1, result_unit = $2, 
           is_abnormal = $3, abnormality_type = $4,
           performed_by = $5, performed_at = CURRENT_TIMESTAMP,
           status = 'completed'
       WHERE id = $6`,
      [resultValue, resultUnit, isAbnormal, abnormalityType, performedBy, orderItemId]
    );
    
    // Check if all items in order are complete
    const pendingItems = await client.query(
      `SELECT COUNT(*) as count 
       FROM lab_order_items 
       WHERE order_id = $1 AND status != 'completed'`,
      [test.order_id]
    );
    
    if (pendingItems.rows[0].count === 0) {
      await client.query(
        `UPDATE lab_orders SET status = 'completed' WHERE id = $1`,
        [test.order_id]
      );
    }
    
    // Send critical alert if needed
    if (abnormalityType === 'critical_low' || abnormalityType === 'critical_high') {
      await sendCriticalAlert({
        type: 'critical_lab_result',
        patientId: test.patient_id,
        testName: test.test_name,
        value: resultValue,
        unit: resultUnit,
        abnormalityType
      });
    }
    
    await client.query('COMMIT');
    
    res.json({
      success: true,
      message: 'Lab result submitted successfully'
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error submitting lab result:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to submit lab result' 
    });
  } finally {
    client.release();
  }
});

function checkAbnormalResult(value, referenceRanges) {
  const numValue = parseFloat(value);
  const ranges = referenceRanges.default || referenceRanges;
  
  if (numValue < ranges.critical_low) {
    return { isAbnormal: true, abnormalityType: 'critical_low' };
  } else if (numValue < ranges.min) {
    return { isAbnormal: true, abnormalityType: 'low' };
  } else if (numValue > ranges.critical_high) {
    return { isAbnormal: true, abnormalityType: 'critical_high' };
  } else if (numValue > ranges.max) {
    return { isAbnormal: true, abnormalityType: 'high' };
  }
  
  return { isAbnormal: false, abnormalityType: null };
}

async function generateLabOrderNumber() {
  const year = new Date().getFullYear();
  const result = await pool.query(
    `SELECT COUNT(*) as count FROM lab_orders 
     WHERE order_number LIKE $1`,
    [`LAB-${year}-%`]
  );
  const count = parseInt(result.rows[0].count) + 1;
  return `LAB-${year}-${String(count).padStart(5, '0')}`;
}

const PORT = process.env.PORT || 3005;
app.listen(PORT, () => {
  console.log(`Lab service running on port ${PORT}`);
});
```

### Month 6: Billing & Insurance Integration

#### Week 21-22: Billing Service
```typescript
// backend/services/billing-service/src/index.ts
import express from 'express';
import { Pool } from
