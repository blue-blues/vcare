# Technical Challenges and Solutions

## 1. Performance Challenges

### Challenge 1.1: High-Volume Concurrent Users
**Problem**: Hospital system needs to handle 10,000+ concurrent users during peak hours.

**Solution**:
```typescript
// Implement connection pooling
import { Pool } from 'pg';
import Redis from 'ioredis';

// Database connection pool
const dbPool = new Pool({
  max: 100, // Maximum number of clients in the pool
  min: 10,  // Minimum number of clients in the pool
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Redis connection pool for caching
const redis = new Redis.Cluster([
  { port: 6379, host: 'redis-node-1' },
  { port: 6379, host: 'redis-node-2' },
  { port: 6379, host: 'redis-node-3' },
], {
  redisOptions: {
    password: process.env.REDIS_PASSWORD,
  },
  enableReadyCheck: true,
  maxRetriesPerRequest: 3,
});

// Implement caching strategy
async function getPatientData(patientId: string) {
  // Try cache first
  const cacheKey = `patient:${patientId}`;
  const cached = await redis.get(cacheKey);
  
  if (cached) {
    return JSON.parse(cached);
  }
  
  // If not in cache, get from database
  const result = await dbPool.query(
    'SELECT * FROM patients WHERE id = $1',
    [patientId]
  );
  
  // Cache for 5 minutes
  await redis.setex(cacheKey, 300, JSON.stringify(result.rows[0]));
  
  return result.rows[0];
}

// Implement request batching
class BatchProcessor {
  private batch: Map<string, Promise<any>> = new Map();
  private timer: NodeJS.Timeout | null = null;
  
  async process(key: string, fn: () => Promise<any>) {
    if (this.batch.has(key)) {
      return this.batch.get(key);
    }
    
    const promise = fn();
    this.batch.set(key, promise);
    
    if (!this.timer) {
      this.timer = setTimeout(() => {
        this.batch.clear();
        this.timer = null;
      }, 100);
    }
    
    return promise;
  }
}
```

### Challenge 1.2: Real-time Data Synchronization
**Problem**: Multiple services need real-time updates when patient data changes.

**Solution**:
```typescript
// Implement event-driven architecture with Kafka
import { Kafka, Producer, Consumer } from 'kafkajs';

const kafka = new Kafka({
  clientId: 'hospital-system',
  brokers: ['kafka-broker-1:9092', 'kafka-broker-2:9092'],
});

// Producer for publishing events
class EventPublisher {
  private producer: Producer;
  
  constructor() {
    this.producer = kafka.producer();
  }
  
  async connect() {
    await this.producer.connect();
  }
  
  async publishPatientUpdate(patientId: string, changes: any) {
    await this.producer.send({
      topic: 'patient-updates',
      messages: [
        {
          key: patientId,
          value: JSON.stringify({
            eventType: 'PATIENT_UPDATED',
            patientId,
            changes,
            timestamp: new Date().toISOString(),
          }),
        },
      ],
    });
  }
}

// Consumer for subscribing to events
class EventSubscriber {
  private consumer: Consumer;
  
  constructor(groupId: string) {
    this.consumer = kafka.consumer({ groupId });
  }
  
  async subscribeToPatientUpdates(handler: (data: any) => Promise<void>) {
    await this.consumer.connect();
    await this.consumer.subscribe({ topic: 'patient-updates', fromBeginning: false });
    
    await this.consumer.run({
      eachMessage: async ({ message }) => {
        const data = JSON.parse(message.value?.toString() || '{}');
        await handler(data);
      },
    });
  }
}

// WebSocket for real-time UI updates
import { Server as SocketServer } from 'socket.io';

class RealtimeNotifier {
  private io: SocketServer;
  
  constructor(server: any) {
    this.io = new SocketServer(server, {
      cors: {
        origin: process.env.ALLOWED_ORIGINS?.split(','),
        credentials: true,
      },
    });
    
    this.setupEventHandlers();
  }
  
  private setupEventHandlers() {
    const subscriber = new EventSubscriber('realtime-notifier');
    
    subscriber.subscribeToPatientUpdates(async (data) => {
      // Notify connected clients
      this.io.to(`patient-${data.patientId}`).emit('patient-update', data);
      
      // Notify doctors treating this patient
      const doctors = await this.getDoctorsForPatient(data.patientId);
      doctors.forEach(doctorId => {
        this.io.to(`doctor-${doctorId}`).emit('patient-update', data);
      });
    });
  }
  
  private async getDoctorsForPatient(patientId: string) {
    // Query to get doctors currently treating this patient
    const result = await dbPool.query(
      `SELECT DISTINCT doctor_id FROM appointments 
       WHERE patient_id = $1 AND status = 'in-progress'`,
      [patientId]
    );
    return result.rows.map(row => row.doctor_id);
  }
}
```

## 2. Data Integrity Challenges

### Challenge 2.1: Preventing Duplicate Records
**Problem**: Preventing duplicate patient registrations and appointments.

**Solution**:
```typescript
// Implement idempotency and duplicate detection
class DuplicateDetector {
  async checkDuplicatePatient(data: any) {
    // Multi-field duplicate check with fuzzy matching
    const query = `
      SELECT id, 
        similarity(first_name || ' ' || last_name, $1) as name_similarity,
        CASE WHEN date_of_birth = $2 THEN 1 ELSE 0 END as dob_match,
        CASE WHEN phone_primary = $3 THEN 1 ELSE 0 END as phone_match,
        CASE WHEN email = $4 THEN 1 ELSE 0 END as email_match
      FROM patients
      WHERE 
        similarity(first_name || ' ' || last_name, $1) > 0.7
        OR date_of_birth = $2
        OR phone_primary = $3
        OR email = $4
    `;
    
    const result = await dbPool.query(query, [
      `${data.firstName} ${data.lastName}`,
      data.dateOfBirth,
      data.phone,
      data.email,
    ]);
    
    // Calculate match score
    const duplicates = result.rows.map(row => ({
      ...row,
      matchScore: 
        row.name_similarity * 0.3 +
        row.dob_match * 0.3 +
        row.phone_match * 0.2 +
        row.email_match * 0.2,
    }));
    
    // Return potential duplicates with score > 0.8
    return duplicates.filter(d => d.matchScore > 0.8);
  }
  
  async preventDuplicateAppointment(doctorId: string, date: string, time: string) {
    // Use database constraints and transactions
    const client = await dbPool.connect();
    
    try {
      await client.query('BEGIN');
      
      // Lock the time slot
      await client.query(
        `SELECT * FROM appointments 
         WHERE doctor_id = $1 AND appointment_date = $2 AND appointment_time = $3
         FOR UPDATE`,
        [doctorId, date, time]
      );
      
      // Check if slot is available
      const existing = await client.query(
        `SELECT id FROM appointments 
         WHERE doctor_id = $1 AND appointment_date = $2 AND appointment_time = $3
         AND status NOT IN ('cancelled', 'no-show')`,
        [doctorId, date, time]
      );
      
      if (existing.rows.length > 0) {
        await client.query('ROLLBACK');
        throw new Error('Slot already booked');
      }
      
      // Proceed with booking
      // ... booking logic
      
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }
}

// Implement idempotency keys for critical operations
class IdempotencyManager {
  async executeOnce(key: string, operation: () => Promise<any>) {
    // Check if operation was already executed
    const existing = await redis.get(`idempotency:${key}`);
    if (existing) {
      return JSON.parse(existing);
    }
    
    // Lock to prevent concurrent execution
    const lock = await redis.set(
      `lock:${key}`,
      '1',
      'NX',
      'EX',
      30 // 30 second lock
    );
    
    if (!lock) {
      // Another process is handling this
      await this.waitForResult(key);
      const result = await redis.get(`idempotency:${key}`);
      return result ? JSON.parse(result) : null;
    }
    
    try {
      // Execute operation
      const result = await operation();
      
      // Store result
      await redis.setex(
        `idempotency:${key}`,
        86400, // 24 hours
        JSON.stringify(result)
      );
      
      return result;
    } finally {
      // Release lock
      await redis.del(`lock:${key}`);
    }
  }
  
  private async waitForResult(key: string, maxWait: number = 5000) {
    const startTime = Date.now();
    while (Date.now() - startTime < maxWait) {
      const result = await redis.get(`idempotency:${key}`);
      if (result) return;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
}
```

### Challenge 2.2: Maintaining Data Consistency Across Services
**Problem**: Ensuring data consistency in a microservices architecture.

**Solution**:
```typescript
// Implement Saga pattern for distributed transactions
class SagaOrchestrator {
  async executeAdmissionSaga(patientId: string, admissionData: any) {
    const sagaId = generateUUID();
    const steps: SagaStep[] = [];
    
    try {
      // Step 1: Reserve bed
      const bedReservation = await this.reserveBed(admissionData.wardId);
      steps.push({
        service: 'ward-service',
        action: 'reserve-bed',
        compensate: () => this.releaseBed(bedReservation.bedId),
      });
      
      // Step 2: Create admission record
      const admission = await this.createAdmission(patientId, bedReservation.bedId);
      steps.push({
        service: 'admission-service',
        action: 'create-admission',
        compensate: () => this.cancelAdmission(admission.id),
      });
      
      // Step 3: Update patient status
      await this.updatePatientStatus(patientId, 'admitted');
      steps.push({
        service: 'patient-service',
        action: 'update-status',
        compensate: () => this.updatePatientStatus(patientId, 'outpatient'),
      });
      
      // Step 4: Create billing record
      const billing = await this.initializeBilling(admission.id);
      steps.push({
        service: 'billing-service',
        action: 'initialize-billing',
        compensate: () => this.cancelBilling(billing.id),
      });
      
      // All steps successful
      await this.commitSaga(sagaId);
      return { success: true, admissionId: admission.id };
      
    } catch (error) {
      // Compensate in reverse order
      console.error(`Saga ${sagaId} failed:`, error);
      
      for (let i = steps.length - 1; i >= 0; i--) {
        try {
          await steps[i].compensate();
        } catch (compensateError) {
          console.error(`Compensation failed for ${steps[i].action}:`, compensateError);
        }
      }
      
      throw new Error('Admission process failed');
    }
  }
}

// Implement event sourcing for audit trail
class EventStore {
  async appendEvent(aggregateId: string, event: any) {
    await dbPool.query(
      `INSERT INTO event_store (aggregate_id, event_type, event_data, created_at)
       VALUES ($1, $2, $3, CURRENT_TIMESTAMP)`,
      [aggregateId, event.type, JSON.stringify(event.data)]
    );
  }
  
  async getEvents(aggregateId: string) {
    const result = await dbPool.query(
      `SELECT * FROM event_store 
       WHERE aggregate_id = $1 
       ORDER BY created_at ASC`,
      [aggregateId]
    );
    return result.rows;
  }
  
  async rebuildState(aggregateId: string) {
    const events = await this.getEvents(aggregateId);
    let state = {};
    
    for (const event of events) {
      state = this.applyEvent(state, event);
    }
    
    return state;
  }
  
  private applyEvent(state: any, event: any) {
    const eventData = JSON.parse(event.event_data);
    
    switch (event.event_type) {
      case 'PATIENT_CREATED':
        return { ...state, ...eventData };
      case 'PATIENT_UPDATED':
        return { ...state, ...eventData };
      case 'APPOINTMENT_BOOKED':
        return {
          ...state,
          appointments: [...(state.appointments || []), eventData],
        };
      default:
        return state;
    }
  }
}
```

## 3. Security Challenges

### Challenge 3.1: Protecting Sensitive Medical Data
**Problem**: Ensuring HIPAA compliance and protecting PHI (Protected Health Information).

**Solution**:
```typescript
// Implement field-level encryption
import crypto from 'crypto';

class EncryptionService {
  private algorithm = 'aes-256-gcm';
  private key: Buffer;
  
  constructor() {
    this.key = Buffer.from(process.env.ENCRYPTION_KEY!, 'hex');
  }
  
  encrypt(text: string): string {
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv(this.algorithm, this.key, iv);
    
    let encrypted = cipher.update(text, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    
    const authTag = cipher.getAuthTag();
    
    return iv.toString('hex') + ':' + authTag.toString('hex') + ':' + encrypted;
  }
  
  decrypt(encryptedData: string): string {
    const parts = encryptedData.split(':');
    const iv = Buffer.from(parts[0], 'hex');
    const authTag = Buffer.from(parts[1], 'hex');
    const encrypted = parts[2];
    
    const decipher = crypto.createDecipheriv(this.algorithm, this.key, iv);
    decipher.setAuthTag(authTag);
    
    let decrypted = decipher.update(encrypted, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    
    return decrypted;
  }
}

// Implement data masking for different user roles
class DataMasking {
  maskPatientData(data: any, userRole: string): any {
    const masked = { ...data };
    
    switch (userRole) {
      case 'receptionist':
        // Mask sensitive medical information
        delete masked.medical_history;
        delete masked.diagnoses;
        masked.ssn = this.maskSSN(masked.ssn);
        break;
        
      case 'billing':
        // Mask medical details but keep insurance info
        delete masked.medical_history;
        delete masked.clinical_notes;
        break;
        
      case 'nurse':
        // Show medical info but mask financial
        delete masked.insurance_details;
        delete masked.billing_information;
        masked.ssn = this.maskSSN(masked.ssn);
        break;
        
      case 'doctor':
        // Full access to medical, limited financial
        masked.ssn = this.maskSSN(masked.ssn);
        break;
        
      default:
        // Minimal access
        return {
          id: masked.id,
          name: masked.first_name + ' ' + masked.last_name,
        };
    }
    
    return masked;
  }
  
  private maskSSN(ssn: string): string {
    if (!ssn) return '';
    return 'XXX-XX-' + ssn.slice(-4);
  }
}

// Implement audit logging for compliance
class AuditLogger {
  async logAccess(userId: string, action: string, resource: string, details: any) {
    await dbPool.query(
      `INSERT INTO audit_log (user_id, action, resource, details, ip_address, timestamp)
       VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)`,
      [userId, action, resource, JSON.stringify(details), this.getClientIP()]
    );
  }
  
  async logDataModification(userId: string, table: string, recordId: string, changes: any) {
    await dbPool.query(
      `INSERT INTO data_audit_log (user_id, table_name, record_id, operation, old_values, new_values, timestamp)
       VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP)`,
      [userId, table, recordId, 'UPDATE', changes.old, changes.new]
    );
  }
  
  private getClientIP(): string {
    // Implementation to get client IP
    return '127.0.0.1';
  }
}
```

### Challenge 3.2: Preventing Unauthorized Access
**Problem**: Implementing robust authentication and authorization.

**Solution**:
```typescript
// Implement multi-factor authentication
import speakeasy from 'speakeasy';
import QRCode from 'qrcode';

class MFAService {
  generateSecret(userId: string) {
    const secret = speakeasy.generateSecret({
      name: `Hospital System (${userId})`,
      issuer: 'Hospital Management System',
    });
    
    return {
      secret: secret.base32,
      qrCode: QRCode.toDataURL(secret.otpauth_url!),
    };
  }
  
  verifyToken(secret: string, token: string): boolean {
    return speakeasy.totp.verify({
      secret,
      encoding: 'base32',
      token,
      window: 2, // Allow 2 time steps tolerance
    });
  }
}

// Implement role-based access control with fine-grained permissions
class AccessControl {
  private permissions = new Map<string, Set<string>>();
  
  constructor() {
    this.loadPermissions();
  }
  
  private loadPermissions() {
    // Doctor permissions
    this.permissions.set('doctor', new Set([
      'patient:read',
      'patient:write:medical',
      'prescription:create',
      'prescription:read',
      'lab:order',
      'lab:read',
    ]));
    
    // Nurse permissions
    this.permissions.set('nurse', new Set([
      'patient:read',
      'patient:write:vitals',
      'prescription:read',
      'lab:read',
    ]));
    
    // Admin permissions
    this.permissions.set('admin', new Set([
      'user:create',
      'user:read',
      'user:update',
      'user:delete',
      'system:configure',
    ]));
  }
  
  hasPermission(userRole: string, permission: string): boolean {
    const rolePermissions = this.permissions.get(userRole);
    if (!rolePermissions) return false;
    
    // Check exact permission
    if (rolePermissions.has(permission)) return true;
    
    // Check wildcard permissions
    const [resource, action, subAction] = permission.split(':');
    if (rolePermissions.has(`${resource}:*`)) return true;
    if (subAction && rolePermissions.has(`${resource}:${action}:*`)) return true;
    
    return false;
  }
  
  async checkResourceAccess(userId: string, resourceType: string, resourceId: string): Promise<boolean> {
    // Check if user has relationship with resource
    switch (resourceType) {
      case 'patient':
        // Check if doctor is treating this patient
        const result = await dbPool.query(
          `SELECT 1 FROM appointments 
           WHERE doctor_id = $1 AND patient_id = $2 
           AND appointment_date >= CURRENT_DATE - INTERVAL '30 days'`,
          [userId, resourceId]
        );
        return result.rows.length > 0;
        
      case 'prescription':
        // Check if user created or is assigned to this prescription
        const prescResult = await dbPool.query(
          `SELECT 1 FROM prescriptions 
           WHERE (doctor_id = $1 OR patient_id = $1) AND id = $2`,
          [userId, resourceId]
        );
        return prescResult.rows.length > 0;
        
      default:
        return false;
    }
  }
}
```

## 4. Scalability Challenges

### Challenge 4.1: Handling Medical Image Storage
**Problem**: Storing and serving large medical images (X-rays, CT scans, MRIs).

**Solution**:
```typescript
// Implement distributed storage with CDN
import AWS from 'aws-sdk';
import sharp from 'sharp';

class MedicalImageStorage {
  private s3: AWS.S3;
  private cloudfront: string;
  
  constructor() {
    this.s3 = new AWS.S3({
      accessKeyId: process.env.AWS_ACCESS_KEY,
      secretAccessKey: process.env.AWS_SECRET_KEY,
      region: process.env.AWS_REGION,
    });
    this.cloudfront = process.env.CLOUDFRONT_URL!;
  }
  
  async uploadMedicalImage(file: Buffer, metadata: any) {
    // Generate unique key
    const key = `medical-images/${metadata.patientId}/${metadata.type}/${Date.now()}.dcm`;
    
    // Create thumbnail for preview
    const thumbnail = await this.createThumbnail(file);
    
    // Upload original to S3
    await this.s3.putObject({
      Bucket: process.env.S3_BUCKET!,
      Key: key,
      Body: file,
      Metadata: {
        patientId: metadata.patientId,
        modality: metadata.modality,
        studyDate: metadata.studyDate,
      },
      ServerSideEncryption: 'AES256',
    }).promise();
    
    // Upload thumbnail
    await this.s3.putObject({
      Bucket: process.env.S3_BUCKET!,
      Key: key.replace('.dcm', '_thumb.jpg'),
      Body: thumbnail,
      ContentType: 'image/jpeg',
    }).promise();
    
    // Store metadata in database
    await dbPool.query(
      `INSERT INTO medical_images (patient_id, s3_key, modality, study_date, file_size)
       VALUES ($1, $2, $3, $4, $5)`,
      [metadata.patientId, key, metadata.modality, metadata.studyDate, file.length]
    );
    
    return {
      imageUrl: `${this.cloudfront}/${key}`,
      thumbnailUrl: `${this.cloudfront}/${key.replace('.dcm', '_thumb.jpg')}`,
    };
  }
  
  private async createThumbnail(dicomBuffer: Buffer): Promise<Buffer> {
    // Convert DICOM to JPEG thumbnail
    // This is simplified - actual implementation would use DICOM parser
    return sharp(dicomBuffer)
      .resize(200, 200)
      .jpeg({ quality: 80 })
      .toBuffer();
  }
  
  async getSignedUrl(key: string, expiresIn: number = 3600): Promise<string> {
    return this.s3.getSignedUrlPromise('getObject', {
      Bucket: process.env.S3_BUCKET!,
      Key: key,
      Expires: expiresIn,
    });
  }
}

// Implement image caching strategy
class ImageCacheManager {
  private cacheDir = '/var/cache/medical-images';
  
  async getCachedImage(imageId: string): Promise<Buffer | null> {
    const cachePath = `${this.cacheDir}/${imageId}`;
    
    try {
      const stats = await fs.stat(cachePath);
      
      // Check if cache is still valid (24 hours)
      if (Date.now() - stats.mtimeMs > 24 * 60 * 60 * 1000) {
        await fs.unlink(cachePath);
        return null;
      }
      
      return await fs.readFile(cachePath);
    } catch {
      return null;
    }
  }
  
  async cacheImage(imageId: string, data: Buffer): Promise<void> {
    const cachePath = `${this.cacheDir}/${imageId}`;
    await fs.writeFile(cachePath, data);
  }
}
```

### Challenge 4.2: Handling Peak Load During Emergencies
**Problem**: System needs to scale rapidly during mass casualty events.

**Solution**:
```typescript
// Implement auto-scaling and load balancing
class AutoScaler {
  async monitorAndScale() {
    const metrics = await this.getSystemMetrics();
    
    if (metrics.cpuUsage > 70 || metrics.memoryUsage > 80) {
      await this.scaleUp();
    } else if (metrics.cpuUsage < 30 && metrics.memoryUsage < 40) {
      await this.scaleDown();
    }
  }
  
  private async scaleUp() {
    // Kubernetes horizontal pod autoscaler
    const k8sApi = new KubernetesClient();
    
    await k8sApi.patch('deployments', 'patient-service', {
      spec: {
        replicas: await this.getCurrentReplicas() + 2,
      },
    });
    
    // Notify load balancer
    await this.updateLoadBalancer();
  }
  
  private async scaleDown() {
    const currentReplicas = await this.getCurrentReplicas();
    if (currentReplicas > 2) {
      // Keep minimum 2 replicas
      await k8sApi.patch('deployments', 'patient-service', {
        spec: {
          replicas: currentReplicas - 1,
        },
      });
    }
  }
}

// Implement circuit breaker for resilience
class CircuitBreaker {
  private failures = 0;
  private lastFailureTime: number = 0;
  private state: 'CLOSED' | 'OPEN' | 'HALF_OPEN' = 'CLOSED';
  private readonly threshold = 5;
  private readonly timeout = 60000; // 1 minute
  
  async execute<T>(fn: () => Promise<T>): Promise<T> {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailureTime > this.timeout) {
        this.state = 'HALF_OPEN';
      } else {
        throw new Error('Circuit breaker is OPEN');
      }
    }
    
    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }
  
  private onSuccess() {
    this.failures = 0;
    this.state = 'CLOSED';
  }
  
  private onFailure() {
    this.failures++;
    this.lastFailureTime = Date.now();
    
    if (this.failures >= this.threshold) {
      this.state = 'OPEN';
    }
  }
}
```

## 5. Integration Challenges

### Challenge 5.1: Integrating with Legacy Systems
**Problem**: Need to integrate with existing hospital systems using HL7.

**Solution**:
```typescript
// HL7 message parser and generator
import hl7 from 'node-hl7-complete';

class HL7Integration {
  parseHL7Message(message: string) {
    const parsed = hl7.parse(message);
    
    // Extract patient information from ADT message
    if (parsed.header.messageType === 'ADT') {
      return {
        patientId: parsed.get('PID.3'),
        firstName: parsed.get('PID.5.2'),
        lastName: parsed.get('PID.5.1'),
        dateOfBirth: this.parseHL7Date(parsed.get('PID.7')),
        gender: parsed.get('PID.8'),
      };
    }
    
    // Extract lab results from ORU message
    if (parsed.header.messageType === 'ORU') {
      return {
        patientId: parsed.get('PID.3'),
        orderNumber: parsed.get('OBR.2'),
        results: this.parseObservations(parsed.get('OBX')),
      };
    }
  }
  
  generateHL7Message(type: string, data: any): string {
    const message = new hl7.Message();
    
    // Set header
    message.header.sendingApplication = 'HMS';
    message.header.sendingFacility = 'HOSPITAL';
    message.header.messageType = type;
    
    switch (type) {
      case 'ADT^A01': // Patient admission
        this.buildAdmissionMessage(message, data);
        break;
      case 'ORM^O01': // Lab order
        this.buildLabOrderMessage(message, data);
        break;
    }
    
    return message.toString();
  }
  
  private buildAdmissionMessage(message: any, data: any) {
    // PID segment
    message.addSegment('PID');
    message.set('PID.3', data.patientId);
    message.set('PID.5.1', data.lastName);
    message.set('PID.5.2', data.firstName);
    message.set('PID.7', this.formatHL7Date(data.dateOfBirth));
    
    // PV1 segment
    message.addSegment('PV1');
    message.set('PV1.2', 'I'); // Inpatient
    message.set('PV1.3', data.wardLocation);
    message.set('PV1.7', data.attendingDoctor);
  }
}

// FHIR integration for modern systems
class FHIRIntegration {
  async createFHIRPatient(patientData: any) {
    const fhirPatient = {
      resourceType: 'Patient',
      identifier: [{
        system: 'http://hospital.com/patients
