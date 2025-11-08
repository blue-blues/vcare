/**
 * API Gateway
 * CRITICAL: Central entry point for all client requests
 * Handles routing, load balancing, and request aggregation
 */

import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import morgan from 'morgan';
import axios from 'axios';
import dotenv from 'dotenv';

import {
  AppError,
  AuthenticationError,
  formatErrorResponse,
  asyncHandler,
  logError,
} from '../../shared/utils/errors';

// Load environment variables
dotenv.config();

const app = express();

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
  credentials: true,
}));
app.use(compression());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(morgan('combined'));

// Global rate limiting
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 1000, // 1000 requests per window
  message: 'Too many requests from this IP, please try again later',
  standardHeaders: true,
  legacyHeaders: false,
});

app.use(globalLimiter);

// Service URLs
const SERVICES = {
  auth: process.env.AUTH_SERVICE_URL || 'http://localhost:3001',
  patient: process.env.PATIENT_SERVICE_URL || 'http://localhost:3002',
  doctor: process.env.DOCTOR_SERVICE_URL || 'http://localhost:3003',
  appointment: process.env.APPOINTMENT_SERVICE_URL || 'http://localhost:3004',
  consultation: process.env.CONSULTATION_SERVICE_URL || 'http://localhost:3005',
  prescription: process.env.PRESCRIPTION_SERVICE_URL || 'http://localhost:3006',
  pharmacy: process.env.PHARMACY_SERVICE_URL || 'http://localhost:3007',
  laboratory: process.env.LABORATORY_SERVICE_URL || 'http://localhost:3008',
  billing: process.env.BILLING_SERVICE_URL || 'http://localhost:3009',
  emergency: process.env.EMERGENCY_SERVICE_URL || 'http://localhost:3010',
  icu: process.env.ICU_SERVICE_URL || 'http://localhost:3011',
  ai: process.env.AI_SERVICE_URL || 'http://localhost:3012',
};

/**
 * Authentication middleware
 */
async function authenticateRequest(req: Request, res: Response, next: NextFunction) {
  try {
    const token = req.headers.authorization?.replace('Bearer ', '');
    
    if (!token) {
      throw new AuthenticationError('No token provided');
    }
    
    // Verify token with auth service
    const response = await axios.post(
      `${SERVICES.auth}/verify`,
      {},
      {
        headers: { Authorization: `Bearer ${token}` },
        timeout: 5000,
      }
    );
    
    if (response.data.success) {
      // Attach user info to request
      req.user = response.data.data;
      next();
    } else {
      throw new AuthenticationError('Invalid token');
    }
  } catch (error) {
    if (axios.isAxiosError(error)) {
      if (error.response?.status === 401) {
        next(new AuthenticationError('Invalid or expired token'));
      } else {
        next(new AppError('Authentication service unavailable', 503));
      }
    } else {
      next(error);
    }
  }
}

/**
 * Proxy request to service
 */
async function proxyRequest(
  serviceUrl: string,
  path: string,
  method: string,
  req: Request
): Promise<any> {
  try {
    const response = await axios({
      method: method as any,
      url: `${serviceUrl}${path}`,
      data: req.body,
      params: req.query,
      headers: {
        ...req.headers,
        host: undefined, // Remove host header
      },
      timeout: 30000, // 30 seconds
    });
    
    return response.data;
  } catch (error) {
    if (axios.isAxiosError(error)) {
      if (error.response) {
        throw new AppError(
          error.response.data.error?.message || 'Service error',
          error.response.status
        );
      } else if (error.code === 'ECONNREFUSED') {
        throw new AppError('Service unavailable', 503);
      } else if (error.code === 'ETIMEDOUT') {
        throw new AppError('Service timeout', 504);
      }
    }
    throw error;
  }
}

/**
 * Health check
 */
app.get('/health', asyncHandler(async (req: Request, res: Response) => {
  // Check all services
  const serviceHealth = await Promise.allSettled(
    Object.entries(SERVICES).map(async ([name, url]) => {
      try {
        const response = await axios.get(`${url}/health`, { timeout: 3000 });
        return { name, status: 'healthy', url };
      } catch (error) {
        return { name, status: 'unhealthy', url };
      }
    })
  );
  
  const services = serviceHealth.map(result => 
    result.status === 'fulfilled' ? result.value : { status: 'error' }
  );
  
  const allHealthy = services.every(s => s.status === 'healthy');
  
  res.status(allHealthy ? 200 : 503).json({
    success: allHealthy,
    gateway: 'healthy',
    services,
    timestamp: new Date().toISOString(),
  });
}));

/**
 * Authentication routes (public)
 */
app.post('/api/auth/register', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.auth, '/register', 'POST', req);
  res.status(201).json(data);
}));

app.post('/api/auth/login', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.auth, '/login', 'POST', req);
  res.json(data);
}));

app.post('/api/auth/logout', authenticateRequest, asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.auth, '/logout', 'POST', req);
  res.json(data);
}));

app.post('/api/auth/mfa/setup', authenticateRequest, asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.auth, '/mfa/setup', 'POST', req);
  res.json(data);
}));

app.post('/api/auth/mfa/enable', authenticateRequest, asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.auth, '/mfa/enable', 'POST', req);
  res.json(data);
}));

/**
 * Patient routes (protected)
 */
app.use('/api/patients', authenticateRequest);

app.post('/api/patients', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.patient, '/', 'POST', req);
  res.status(201).json(data);
}));

app.get('/api/patients/:id', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.patient, `/${req.params.id}`, 'GET', req);
  res.json(data);
}));

app.put('/api/patients/:id', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.patient, `/${req.params.id}`, 'PUT', req);
  res.json(data);
}));

app.get('/api/patients/:id/medical-history', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.patient, `/${req.params.id}/medical-history`, 'GET', req);
  res.json(data);
}));

app.post('/api/patients/:id/allergies', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.patient, `/${req.params.id}/allergies`, 'POST', req);
  res.status(201).json(data);
}));

/**
 * Doctor routes (protected)
 */
app.use('/api/doctors', authenticateRequest);

app.get('/api/doctors', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.doctor, '/', 'GET', req);
  res.json(data);
}));

app.get('/api/doctors/:id', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.doctor, `/${req.params.id}`, 'GET', req);
  res.json(data);
}));

app.get('/api/doctors/:id/availability', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.doctor, `/${req.params.id}/availability`, 'GET', req);
  res.json(data);
}));

/**
 * Appointment routes (protected)
 */
app.use('/api/appointments', authenticateRequest);

app.post('/api/appointments', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.appointment, '/', 'POST', req);
  res.status(201).json(data);
}));

app.get('/api/appointments/:id', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.appointment, `/${req.params.id}`, 'GET', req);
  res.json(data);
}));

app.put('/api/appointments/:id', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.appointment, `/${req.params.id}`, 'PUT', req);
  res.json(data);
}));

app.delete('/api/appointments/:id', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.appointment, `/${req.params.id}`, 'DELETE', req);
  res.json(data);
}));

/**
 * Emergency routes (protected)
 */
app.use('/api/emergency', authenticateRequest);

app.post('/api/emergency/cases', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.emergency, '/cases', 'POST', req);
  res.status(201).json(data);
}));

app.get('/api/emergency/cases/:id', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.emergency, `/cases/${req.params.id}`, 'GET', req);
  res.json(data);
}));

/**
 * Laboratory routes (protected)
 */
app.use('/api/laboratory', authenticateRequest);

app.post('/api/laboratory/orders', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.laboratory, '/orders', 'POST', req);
  res.status(201).json(data);
}));

app.get('/api/laboratory/orders/:id', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.laboratory, `/orders/${req.params.id}`, 'GET', req);
  res.json(data);
}));

/**
 * Billing routes (protected)
 */
app.use('/api/billing', authenticateRequest);

app.post('/api/billing/bills', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.billing, '/bills', 'POST', req);
  res.status(201).json(data);
}));

app.get('/api/billing/bills/:id', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.billing, `/bills/${req.params.id}`, 'GET', req);
  res.json(data);
}));

app.post('/api/billing/payments', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.billing, '/payments', 'POST', req);
  res.status(201).json(data);
}));

/**
 * AI routes (protected)
 */
app.use('/api/ai', authenticateRequest);

app.post('/api/ai/diagnosis', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.ai, '/diagnosis', 'POST', req);
  res.json(data);
}));

app.post('/api/ai/drug-interactions', asyncHandler(async (req: Request, res: Response) => {
  const data = await proxyRequest(SERVICES.ai, '/drug-interactions', 'POST', req);
  res.json(data);
}));

/**
 * 404 handler
 */
app.use((req: Request, res: Response) => {
  res.status(404).json({
    success: false,
    error: {
      message: 'Route not found',
      code: 'NOT_FOUND',
      statusCode: 404,
      path: req.path,
      timestamp: new Date().toISOString(),
    },
  });
});

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
const PORT = process.env.API_GATEWAY_PORT || 3000;

app.listen(PORT, () => {
  console.log(`🌐 API Gateway running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log('Service URLs:');
  Object.entries(SERVICES).forEach(([name, url]) => {
    console.log(`  - ${name}: ${url}`);
  });
});

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
