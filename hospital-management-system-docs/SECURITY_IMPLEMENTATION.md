# Security Implementation Guide

## 1. Security Architecture Overview

### 1.1 Defense in Depth Strategy
```yaml
Security Layers:
  1. Network Security:
     - Firewall rules
     - VPN access
     - Network segmentation
     - DDoS protection
     
  2. Application Security:
     - Input validation
     - Output encoding
     - Authentication & Authorization
     - Session management
     
  3. Data Security:
     - Encryption at rest
     - Encryption in transit
     - Data masking
     - Tokenization
     
  4. Operational Security:
     - Monitoring & Logging
     - Incident response
     - Vulnerability management
     - Security training
```

## 2. Authentication Implementation

### 2.1 Multi-Factor Authentication (MFA)
```typescript
// MFA Implementation with TOTP
import speakeasy from 'speakeasy';
import QRCode from 'qrcode';
import crypto from 'crypto';

class MFAService {
  // Generate MFA secret for user
  async setupMFA(userId: string): Promise<{secret: string, qrCode: string}> {
    // Generate secret
    const secret = speakeasy.generateSecret({
      name: `HMS:${userId}`,
      issuer: 'Hospital Management System',
      length: 32
    });
    
    // Store encrypted secret
    const encryptedSecret = this.encryptSecret(secret.base32);
    await this.storeMFASecret(userId, encryptedSecret);
    
    // Generate QR code
    const qrCode = await QRCode.toDataURL(secret.otpauth_url!);
    
    // Generate backup codes
    const backupCodes = this.generateBackupCodes();
    await this.storeBackupCodes(userId, backupCodes);
    
    return {
      secret: secret.base32,
      qrCode,
      backupCodes
    };
  }
  
  // Verify TOTP token
  async verifyTOTP(userId: string, token: string): Promise<boolean> {
    const encryptedSecret = await this.getMFASecret(userId);
    const secret = this.decryptSecret(encryptedSecret);
    
    // Verify with time window
    const verified = speakeasy.totp.verify({
      secret,
      encoding: 'base32',
      token,
      window: 2 // Allow 2 time steps (60 seconds) tolerance
    });
    
    if (verified) {
      // Prevent token reuse
      await this.markTokenAsUsed(userId, token);
      return true;
    }
    
    // Check backup codes
    return this.verifyBackupCode(userId, token);
  }
  
  // Generate backup codes
  private generateBackupCodes(count: number = 10): string[] {
    const codes: string[] = [];
    for (let i = 0; i < count; i++) {
      codes.push(crypto.randomBytes(4).toString('hex').toUpperCase());
    }
    return codes;
  }
  
  // Encrypt secret for storage
  private encryptSecret(secret: string): string {
    const algorithm = 'aes-256-gcm';
    const key = Buffer.from(process.env.MFA_ENCRYPTION_KEY!, 'hex');
    const iv = crypto.randomBytes(16);
    
    const cipher = crypto.createCipheriv(algorithm, key, iv);
    let encrypted = cipher.update(secret, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    
    const authTag = cipher.getAuthTag();
    
    return iv.toString('hex') + ':' + authTag.toString('hex') + ':' + encrypted;
  }
  
  // Decrypt secret
  private decryptSecret(encryptedData: string): string {
    const parts = encryptedData.split(':');
    const iv = Buffer.from(parts[0], 'hex');
    const authTag = Buffer.from(parts[1], 'hex');
    const encrypted = parts[2];
    
    const algorithm = 'aes-256-gcm';
    const key = Buffer.from(process.env.MFA_ENCRYPTION_KEY!, 'hex');
    
    const decipher = crypto.createDecipheriv(algorithm, key, iv);
    decipher.setAuthTag(authTag);
    
    let decrypted = decipher.update(encrypted, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    
    return decrypted;
  }
}
```

### 2.2 Biometric Authentication
```typescript
// Biometric authentication for mobile apps
class BiometricAuth {
  // Fingerprint authentication
  async authenticateWithFingerprint(userId: string, fingerprintData: Buffer): Promise<boolean> {
    try {
      // Get stored fingerprint template
      const storedTemplate = await this.getFingerprintTemplate(userId);
      
      // Compare using fingerprint matching algorithm
      const matchScore = await this.compareFingerprints(fingerprintData, storedTemplate);
      
      // Threshold for match (adjustable based on security requirements)
      const MATCH_THRESHOLD = 0.95;
      
      if (matchScore >= MATCH_THRESHOLD) {
        await this.logSuccessfulAuth(userId, 'fingerprint');
        return true;
      }
      
      await this.logFailedAuth(userId, 'fingerprint');
      return false;
    } catch (error) {
      console.error('Fingerprint authentication error:', error);
      return false;
    }
  }
  
  // Face recognition
  async authenticateWithFace(userId: string, faceImage: Buffer): Promise<boolean> {
    try {
      // Extract face features using AI model
      const faceFeatures = await this.extractFaceFeatures(faceImage);
      
      // Get stored face template
      const storedFeatures = await this.getFaceTemplate(userId);
      
      // Calculate similarity
      const similarity = this.calculateCosineSimilarity(faceFeatures, storedFeatures);
      
      // Liveness detection to prevent photo attacks
      const isLive = await this.performLivenessDetection(faceImage);
      
      if (similarity >= 0.9 && isLive) {
        await this.logSuccessfulAuth(userId, 'face');
        return true;
      }
      
      await this.logFailedAuth(userId, 'face');
      return false;
    } catch (error) {
      console.error('Face authentication error:', error);
      return false;
    }
  }
  
  // Liveness detection
  private async performLivenessDetection(image: Buffer): Promise<boolean> {
    // Implement anti-spoofing checks
    // - Eye blink detection
    // - Head movement tracking
    // - Texture analysis for photo detection
    // - 3D depth analysis
    
    // Simplified implementation
    const livenessScore = await this.calculateLivenessScore(image);
    return livenessScore > 0.8;
  }
}
```

## 3. Authorization & Access Control

### 3.1 Role-Based Access Control (RBAC)
```typescript
// RBAC Implementation
class RBACService {
  private roleHierarchy: Map<string, string[]> = new Map();
  private permissions: Map<string, Set<string>> = new Map();
  
  constructor() {
    this.initializeRoles();
  }
  
  private initializeRoles() {
    // Define role hierarchy
    this.roleHierarchy.set('super_admin', ['admin']);
    this.roleHierarchy.set('admin', ['doctor', 'nurse', 'staff']);
    this.roleHierarchy.set('doctor', ['medical_reader']);
    this.roleHierarchy.set('nurse', ['medical_reader']);
    
    // Define permissions for each role
    this.permissions.set('super_admin', new Set([
      'system:*',
      'user:*',
      'audit:*'
    ]));
    
    this.permissions.set('admin', new Set([
      'user:create',
      'user:read',
      'user:update',
      'user:delete',
      'report:*',
      'config:*'
    ]));
    
    this.permissions.set('doctor', new Set([
      'patient:read',
      'patient:write:medical',
      'prescription:create',
      'prescription:read',
      'prescription:update',
      'lab:order',
      'lab:read',
      'consultation:*',
      'medical_record:*'
    ]));
    
    this.permissions.set('nurse', new Set([
      'patient:read',
      'patient:write:vitals',
      'prescription:read',
      'lab:read',
      'medical_record:read',
      'medication:administer'
    ]));
    
    this.permissions.set('receptionist', new Set([
      'patient:create',
      'patient:read:basic',
      'patient:update:contact',
      'appointment:*',
      'billing:read'
    ]));
    
    this.permissions.set('pharmacist', new Set([
      'prescription:read',
      'prescription:dispense',
      'inventory:*',
      'drug_interaction:check'
    ]));
  }
  
  // Check if user has permission
  async hasPermission(userId: string, permission: string): Promise<boolean> {
    const userRoles = await this.getUserRoles(userId);
    
    for (const role of userRoles) {
      if (this.roleHasPermission(role, permission)) {
        return true;
      }
      
      // Check inherited permissions
      const inheritedRoles = this.roleHierarchy.get(role) || [];
      for (const inheritedRole of inheritedRoles) {
        if (this.roleHasPermission(inheritedRole, permission)) {
          return true;
        }
      }
    }
    
    return false;
  }
  
  private roleHasPermission(role: string, permission: string): boolean {
    const rolePermissions = this.permissions.get(role);
    if (!rolePermissions) return false;
    
    // Check exact permission
    if (rolePermissions.has(permission)) return true;
    
    // Check wildcard permissions
    const parts = permission.split(':');
    for (let i = parts.length; i > 0; i--) {
      const wildcardPermission = parts.slice(0, i - 1).join(':') + ':*';
      if (rolePermissions.has(wildcardPermission)) return true;
    }
    
    return false;
  }
  
  // Get user roles from database
  private async getUserRoles(userId: string): Promise<string[]> {
    const result = await dbPool.query(
      `SELECT r.name FROM roles r
       JOIN user_roles ur ON r.id = ur.role_id
       WHERE ur.user_id = $1 AND ur.expires_at > NOW()`,
      [userId]
    );
    return result.rows.map(row => row.name);
  }
}
```

### 3.2 Attribute-Based Access Control (ABAC)
```typescript
// ABAC for fine-grained access control
class ABACService {
  async evaluateAccess(
    subject: any,  // User attributes
    resource: any, // Resource attributes
    action: string,
    environment: any // Environmental attributes
  ): Promise<boolean> {
    // Load policies
    const policies = await this.loadPolicies(resource.type);
    
    for (const policy of policies) {
      if (this.evaluatePolicy(policy, subject, resource, action, environment)) {
        return true;
      }
    }
    
    return false;
  }
  
  private evaluatePolicy(
    policy: any,
    subject: any,
    resource: any,
    action: string,
    environment: any
  ): boolean {
    // Check action
    if (!policy.actions.includes(action)) return false;
    
    // Evaluate subject conditions
    if (!this.evaluateConditions(policy.subjectConditions, subject)) return false;
    
    // Evaluate resource conditions
    if (!this.evaluateConditions(policy.resourceConditions, resource)) return false;
    
    // Evaluate environmental conditions
    if (!this.evaluateConditions(policy.environmentConditions, environment)) return false;
    
    return true;
  }
  
  private evaluateConditions(conditions: any[], attributes: any): boolean {
    for (const condition of conditions) {
      const value = this.getAttributeValue(attributes, condition.attribute);
      
      switch (condition.operator) {
        case 'equals':
          if (value !== condition.value) return false;
          break;
        case 'contains':
          if (!value.includes(condition.value)) return false;
          break;
        case 'greater_than':
          if (value <= condition.value) return false;
          break;
        case 'in':
          if (!condition.value.includes(value)) return false;
          break;
        case 'between':
          if (value < condition.value[0] || value > condition.value[1]) return false;
          break;
      }
    }
    
    return true;
  }
  
  private getAttributeValue(attributes: any, path: string): any {
    const parts = path.split('.');
    let value = attributes;
    
    for (const part of parts) {
      value = value[part];
      if (value === undefined) return null;
    }
    
    return value;
  }
}

// Example ABAC policy
const examplePolicy = {
  id: 'policy-1',
  description: 'Doctors can access their patients medical records during working hours',
  actions: ['read', 'write'],
  subjectConditions: [
    { attribute: 'role', operator: 'equals', value: 'doctor' },
    { attribute: 'department', operator: 'in', value: ['cardiology', 'general'] }
  ],
  resourceConditions: [
    { attribute: 'type', operator: 'equals', value: 'medical_record' },
    { attribute: 'patient.assigned_doctor', operator: 'equals', value: '${subject.id}' }
  ],
  environmentConditions: [
    { attribute: 'time', operator: 'between', value: ['08:00', '18:00'] },
    { attribute: 'location', operator: 'equals', value: 'hospital_network' }
  ]
};
```

## 4. Data Protection

### 4.1 Encryption Implementation
```typescript
// Field-level encryption for sensitive data
class DataEncryption {
  private masterKey: Buffer;
  private algorithm = 'aes-256-gcm';
  
  constructor() {
    // Load master key from secure key management service
    this.masterKey = this.loadMasterKey();
  }
  
  // Encrypt sensitive fields
  async encryptPatientData(data: any): Promise<any> {
    const encryptedData = { ...data };
    
    // Fields to encrypt
    const sensitiveFields = ['ssn', 'medical_history', 'diagnosis', 'credit_card'];
    
    for (const field of sensitiveFields) {
      if (data[field]) {
        encryptedData[field] = await this.encryptField(data[field]);
      }
    }
    
    return encryptedData;
  }
  
  // Decrypt sensitive fields
  async decryptPatientData(data: any): Promise<any> {
    const decryptedData = { ...data };
    
    const sensitiveFields = ['ssn', 'medical_history', 'diagnosis', 'credit_card'];
    
    for (const field of sensitiveFields) {
      if (data[field] && this.isEncrypted(data[field])) {
        decryptedData[field] = await this.decryptField(data[field]);
      }
    }
    
    return decryptedData;
  }
  
  private async encryptField(value: string): Promise<string> {
    // Generate data encryption key (DEK)
    const dek = crypto.randomBytes(32);
    
    // Encrypt DEK with master key (key wrapping)
    const encryptedDek = await this.wrapKey(dek);
    
    // Encrypt data with DEK
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv(this.algorithm, dek, iv);
    
    let encrypted = cipher.update(value, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    
    const authTag = cipher.getAuthTag();
    
    // Combine encrypted DEK, IV, auth tag, and encrypted data
    return `ENC:${encryptedDek}:${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted}`;
  }
  
  private async decryptField(encryptedValue: string): Promise<string> {
    if (!this.isEncrypted(encryptedValue)) {
      return encryptedValue;
    }
    
    const parts = encryptedValue.split(':');
    const encryptedDek = parts[1];
    const iv = Buffer.from(parts[2], 'hex');
    const authTag = Buffer.from(parts[3], 'hex');
    const encrypted = parts[4];
    
    // Unwrap DEK
    const dek = await this.unwrapKey(encryptedDek);
    
    // Decrypt data
    const decipher = crypto.createDecipheriv(this.algorithm, dek, iv);
    decipher.setAuthTag(authTag);
    
    let decrypted = decipher.update(encrypted, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    
    return decrypted;
  }
  
  private isEncrypted(value: string): boolean {
    return value && value.startsWith('ENC:');
  }
  
  // Key wrapping for DEK protection
  private async wrapKey(key: Buffer): Promise<string> {
    const cipher = crypto.createCipheriv('aes-256-wrap', this.masterKey, Buffer.alloc(8, 0xa6));
    const wrapped = Buffer.concat([cipher.update(key), cipher.final()]);
    return wrapped.toString('base64');
  }
  
  private async unwrapKey(wrappedKey: string): Promise<Buffer> {
    const decipher = crypto.createDecipheriv('aes-256-wrap', this.masterKey, Buffer.alloc(8, 0xa6));
    const key = Buffer.concat([
      decipher.update(Buffer.from(wrappedKey, 'base64')),
      decipher.final()
    ]);
    return key;
  }
  
  private loadMasterKey(): Buffer {
    // In production, load from AWS KMS, Azure Key Vault, or HSM
    // This is a simplified example
    return Buffer.from(process.env.MASTER_ENCRYPTION_KEY!, 'hex');
  }
}
```

### 4.2 Data Masking and Anonymization
```typescript
// Data masking for different access levels
class DataMasking {
  // Mask PII based on user role
  maskData(data: any, userRole: string, purpose: string): any {
    const maskedData = { ...data };
    
    const maskingRules = this.getMaskingRules(userRole, purpose);
    
    for (const rule of maskingRules) {
      if (maskedData[rule.field]) {
        maskedData[rule.field] = this.applyMask(maskedData[rule.field], rule.type);
      }
    }
    
    return maskedData;
  }
  
  private getMaskingRules(role: string, purpose: string): any[] {
    const rules = {
      'receptionist': [
        { field: 'ssn', type: 'partial' },
        { field: 'medical_history', type: 'remove' },
        { field: 'diagnosis', type: 'remove' },
        { field: 'credit_card', type: 'partial' }
      ],
      'billing': [
        { field: 'ssn', type: 'partial' },
        { field: 'medical_details', type: 'remove' },
        { field: 'credit_card', type: 'partial' }
      ],
      'researcher': [
        { field: 'name', type: 'anonymize' },
        { field: 'ssn', type: 'remove' },
        { field: 'address', type: 'generalize' },
        { field: 'phone', type: 'remove' },
        { field: 'email', type: 'remove' }
      ]
    };
    
    return rules[role] || [];
  }
  
  private applyMask(value: any, type: string): any {
    switch (type) {
      case 'partial':
        return this.partialMask(value);
      case 'remove':
        return null;
      case 'anonymize':
        return this.anonymize(value);
      case 'generalize':
        return this.generalize(value);
      case 'hash':
        return this.hashValue(value);
      default:
        return value;
    }
  }
  
  private partialMask(value: string): string {
    if (value.length <= 4) return '****';
    
    // Show only last 4 characters
    return '*'.repeat(value.length - 4) + value.slice(-4);
  }
  
  private anonymize(value: string): string {
    // Generate consistent anonymous ID
    const hash = crypto.createHash('sha256').update(value).digest('hex');
    return `ANON_${hash.substring(0, 8)}`;
  }
  
  private generalize(value: string): string {
    // For addresses, show only city and state
    // For ages, show range (e.g., 30-40)
    // Implementation depends on data type
    return value.split(',')[0]; // Simplified
  }
  
  private hashValue(value: string): string {
    return crypto.createHash('sha256').update(value).digest('hex');
  }
}

// Data anonymization for analytics
class DataAnonymization {
  // K-anonymity implementation
  async achieveKAnonymity(dataset: any[], k: number): Promise<any[]> {
    // Identify quasi-identifiers
    const quasiIdentifiers = ['age', 'gender', 'zipcode'];
    
    // Group records by quasi-identifiers
    const groups = this.groupByQuasiIdentifiers(dataset, quasiIdentifiers);
    
    // Generalize groups with less than k records
    const anonymized = [];
    for (const group of groups) {
      if (group.length < k) {
        // Generalize this group
        const generalized = this.generalizeGroup(group, quasiIdentifiers);
        anonymized.push(...generalized);
      } else {
        anonymized.push(...group);
      }
    }
    
    return anonymized;
  }
  
  // Differential privacy
  addDifferentialPrivacy(value: number, epsilon: number = 1.0): number {
    // Add Laplace noise
    const sensitivity = 1; // Depends on query
    const scale = sensitivity / epsilon;
    const noise = this.laplacianNoise(scale);
    
    return value + noise;
  }
  
  private laplacianNoise(scale: number): number {
    const u = Math.random() - 0.5;
    return -scale * Math.sign(u) * Math.log(1 - 2 * Math.abs(u));
  }
}
```

## 5. Security Monitoring

### 5.1 Intrusion Detection System
```typescript
// Real-time intrusion detection
class IntrusionDetection {
  private anomalyDetector: AnomalyDetector;
  private threatIntelligence: ThreatIntelligence;
  
  async monitorActivity(event: SecurityEvent): Promise<void> {
    // Check for known attack patterns
    const threatMatch = await this.threatIntelligence.checkThreat(event);
    if (threatMatch) {
      await this.handleThreat(threatMatch);
      return;
    }
    
    // Anomaly detection
    const anomalyScore = await this.anomalyDetector.analyze(event);
    if (anomalyScore > 0.8) {
      await this.handleAnomaly(event, anomalyScore);
    }
    
    // Behavioral analysis
    await this.analyzeBehavior(event);
  }
  
  private async analyzeBehavior(event: SecurityEvent): Promise<void> {
    // Check for suspicious patterns
    const patterns = [
      this.checkBruteForce(event),
      this.checkPrivilegeEscalation(event),
      this.checkDataExfiltration(event),
      this.checkSQLInjection(event),
      this.checkXSS(event)
    ];
    
    const threats = await Promise.all(patterns);
    const detectedThreats = threats.filter(t => t !== null);
    
    if (detectedThreats.length > 0) {
      await this.respondToThreats(detectedThreats);
    }
  }
  
  private async checkBruteForce(event: SecurityEvent): Promise<Threat | null> {
    const recentAttempts = await this.getRecentLoginAttempts(event.userId);
    
    if (recentAttempts.failed >= 5 && recentAttempts.timeWindow <= 300) {
      return {
        type: 'BRUTE_FORCE',
        severity: 'HIGH',
        userId: event.userId,
        details: `${recentAttempts.failed} failed login attempts in ${recentAttempts.timeWindow} seconds`
      };
    }
    
    return null;
  }
  
  private async checkDataExfiltration(event: SecurityEvent): Promise<Threat | null> {
    // Check for unusual data access patterns
    const accessPattern = await this.analyzeDataAccess(event.userId);
    
    if (accessPattern.volumeAnomaly || accessPattern.timeAnomaly) {
      return {
        type: 'DATA_EXFILTRATION',
        severity: 'CRITICAL',
        userId: event.userId,
        details: 'Unusual data access pattern detected'
      };
    }
    
    return null;
  }
  
  private async respondToThreats(threats: Threat[]): Promise<void> {
    for (const threat of threats) {
      switch (threat.severity) {
        case 'CRITICAL':
          // Immediate action
          await this.blockUser(threat.userId);
          await this.alertSecurityTeam(threat);
          await this.createIncident(threat);
          break;
          
        case 'HIGH':
          // Elevated monitoring
          await this.increaseMonitoring(threat.userId);
          await this.requireMFA(threat.userId);
          await this.alertSecurityTeam(threat);
          break;
          
        case 'MEDIUM':
          // Log and monitor
          await this.logThreat(threat);
          await this.increaseMonitoring(threat.userId);
          break;
          
        case 'LOW':
          // Log only
          await this.logThreat(threat);
          break;
      }
    }
  }
}

// Security Information and Event Management (SIEM)
class SIEM {
  async correlateEvents(events: SecurityEvent[]): Promise<SecurityIncident[]> {
    const incidents: SecurityIncident[] = [];
    
    // Time-based correlation
    const timeCorrelated = this.correlateByTime(events, 300); // 5 minute window
    
    // User-based correlation
    const userCorrelated = this.correlateByUser(events);
    
    // Pattern-based correlation
    const patternCorrelated = this.correlateByPattern(events);
    
    // Merge correlations
    const allCorrelations = [...timeCorrelated, ...userCorrelated, ...patternCorrelated];
    
    // Score and prioritize incidents
    for (const correlation of allCorrelations) {
      const incident = this.createIncidentFromCorrelation(correlation);
      incident.priority = this.calculatePriority(incident);
      incidents.push(incident);
    }
    
    return incidents.sort((a, b) => b.priority - a.priority);
  }
  
  private calculatePriority(incident: SecurityIncident): number {
    let priority = 0;
    
    // Factor in severity
    priority += incident.severity * 10;
    
    // Factor in affected assets
    priority += incident.affectedAssets.length * 2;
    
    // Factor in user privilege level
    if (incident.involvedUsers.some(u => u.isAdmin)) {
      priority += 20;
    }
    
    // Factor in data sensitivity
    if (incident.involvesPHI) {
      priority += 15;
    }
    
    return priority;
  }
}
```

## 6. Compliance & Audit

### 6.1 HIPAA Compliance Implementation
```typescript
// HIPAA compliance monitoring
class HIPAACompliance {
  // Audit log implementation
  async logPHIAccess(
    userId: string,
    patientId: string,
    action: string,
    data: any
  ): Promise<void> {
    const logEntry = {
      timestamp: new Date().toISOString(),
      userId,
      patientId,
      action,
      dataAccessed: this.sanitizeForLog(data),
      ipAddress: this.getClientIP(),
      userAgent: this.getUserAgent(),
      sessionId: this.getSessionId()
    };
    
    // Store in immutable audit log
    await this.storeAuditLog(logEntry);
    
    // Check for compliance violations
    await this.checkComplianceViolations(logEntry);
  }
  
  // Minimum necessary access
  async enforceMinimumNecessary(
    userId: string,
    requestedData: string[],
    purpose: string
  ): Promise<string[]> {
    const userRole = await this.getUserRole(userId);
    const allowedFields = this.getMinimumNecessaryFields(userRole, purpose);
    
    return requestedData.filter(field => allowedFields.includes(field));
  }
  
  // Patient consent management
  async checkConsent(
    patientId: string,
    dataType: string,
    purpose: string
  ): Promise<boolean> {
    const consent = await this.getPatientConsent(patientId);
    
    // Check if consent covers this data type and purpose
    return consent.some(c => 
      c.dataTypes.includes(dataType) &&
      c.purposes.includes(purpose) &&
      c.status === 'active' &&
      new Date(c.expiresAt) > new Date()
    );
  }
  
  // Data retention policy
  async enforceRetentionPolicy(): Promise<void> {
    // Medical records: 7 years
    await this.archiveOldRecords('medical_records', 7);
    
    // Billing records: 7 years
    await this.archiveOldRecords('billing', 7);
    
    // Audit logs: 6 years
    await this.archiveOldRecords('audit_logs', 6);
    
    // Temporary data: 30 days
    await this.purgeTemporaryData(30);
  }
  
  // Breach notification
  async handleDataBreach(breach: DataBreach): Promise<void> {
    // Immediate containment
    await this.containBreach(breach);
    
    // Assessment
    const assessment = await this.assessBreach(breach);
    
    if (assessment.affectedRecords >= 500) {
      // Notify HHS immediately
      await this.notifyHHS(breach, assessment);
    }
    
    // Notify affected individuals within 60 days
