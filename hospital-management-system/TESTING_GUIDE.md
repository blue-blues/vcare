# 🧪 Hospital Management System - Critical-Path Testing Guide

## ⚠️ IMPORTANT
This is a **LIFE-CRITICAL healthcare system**. All critical paths must be tested before production use.

---

## 📋 Testing Checklist

### Phase 1: Environment Setup ✅
- [ ] PostgreSQL installed and running
- [ ] Redis installed and running
- [ ] Node.js 18+ installed
- [ ] Dependencies installed
- [ ] Environment variables configured

### Phase 2: Database Testing ✅
- [ ] All 7 schemas executed successfully
- [ ] Tables created (53 tables)
- [ ] Constraints working
- [ ] Triggers functioning
- [ ] Functions operational

### Phase 3: Service Testing ✅
- [ ] Auth Service running
- [ ] API Gateway running
- [ ] Patient Service running
- [ ] Doctor Service running
- [ ] Appointment Service running

### Phase 4: Critical Workflows ✅
- [ ] User registration
- [ ] User login with JWT
- [ ] MFA setup and verification
- [ ] Patient creation
- [ ] Allergy management with alerts
- [ ] Appointment booking
- [ ] Conflict detection

---

## 🚀 Step-by-Step Testing Instructions

### STEP 1: Environment Setup (5 minutes)

```bash
# Navigate to project
cd hospital-management-system

# Install dependencies
npm install
cd backend && npm install && cd ..

# Copy environment file
cp .env.example .env

# Edit .env - IMPORTANT: Set these values
# DB_PASSWORD=your_secure_password
# REDIS_PASSWORD=your_redis_password
# JWT_SECRET=your_256_bit_secret
# JWT_REFRESH_SECRET=your_256_bit_refresh_secret
```

**Verify:**
```bash
# Check PostgreSQL
psql --version
pg_isready

# Check Redis
redis-cli ping
# Should return: PONG

# Check Node.js
node --version
# Should be 18+
```

---

### STEP 2: Database Setup (10 minutes)

```bash
# Create database
createdb hospital_management

# Create user
psql -c "CREATE USER hms_admin WITH ENCRYPTED PASSWORD 'your_secure_password';"
psql -c "GRANT ALL PRIVILEGES ON DATABASE hospital_management TO hms_admin;"

# Execute schemas IN ORDER (CRITICAL!)
psql -U hms_admin -d hospital_management -f database/schemas/001_core_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/002_clinical_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/003_appointments_consultations_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/004_laboratory_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/005_pharmacy_inventory_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/006_billing_insurance_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/007_emergency_icu_schema.sql
```

**Verify Database:**
```bash
# Connect to database
psql -U hms_admin -d hospital_management

# Check tables
\dt core.*
\dt clinical.*
\dt billing.*
\dt inventory.*
\dt emergency.*

# Verify table counts
SELECT 
  schemaname,
  COUNT(*) as table_count
FROM pg_tables 
WHERE schemaname IN ('core', 'clinical', 'billing', 'inventory', 'emergency')
GROUP BY schemaname;

# Should show:
# core: 10 tables
# clinical: 16 tables
# billing: 7 tables
# inventory: 9 tables
# emergency: 7 tables

# Test a function
SELECT generate_appointment_number();
# Should return something like: APT-2024-000001

# Exit
\q
```

---

### STEP 3: Start Services (5 minutes)

**Terminal 1: Auth Service**
```bash
cd backend/services/auth-service
npm run dev
# Should see: 🔐 Auth Service running on port 3001
```

**Terminal 2: API Gateway**
```bash
cd backend/api-gateway
npm run dev
# Should see: 🌐 API Gateway running on port 3000
```

**Terminal 3: Patient Service**
```bash
cd backend/services/patient-service
npm run dev
# Should see: 👥 Patient Service running on port 3002
```

**Terminal 4: Doctor Service**
```bash
cd backend/services/doctor-service
npm run dev
# Should see: 👨‍⚕️ Doctor Service running on port 3003
```

**Terminal 5: Appointment Service**
```bash
cd backend/services/appointment-service
npm run dev
# Should see: 📅 Appointment Service running on port 3004
```

---

### STEP 4: Health Checks (2 minutes)

```bash
# Test all services
curl http://localhost:3000/health
curl http://localhost:3001/health
curl http://localhost:3002/health
curl http://localhost:3003/health
curl http://localhost:3004/health

# All should return:
# {"success":true,"service":"...","status":"healthy","timestamp":"..."}
```

---

### STEP 5: Critical Workflow Testing (30 minutes)

#### TEST 1: User Registration ✅

```bash
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testdoctor",
    "email": "doctor@hospital.com",
    "password": "SecurePass@123",
    "userType": "doctor",
    "firstName": "John",
    "lastName": "Smith",
    "phone": "+1234567890",
    "dateOfBirth": "1980-01-15",
    "gender": "male"
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "message": "User registered successfully",
  "data": {
    "userId": "...",
    "username": "testdoctor",
    "email": "doctor@hospital.com"
  }
}
```

**Verify in Database:**
```bash
psql -U hms_admin -d hospital_management -c "SELECT id, username, email, user_type FROM core.users WHERE username='testdoctor';"
```

---

#### TEST 2: User Login ✅

```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testdoctor",
    "password": "SecurePass@123"
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refreshToken": "...",
    "user": {
      "userId": "...",
      "username": "testdoctor",
      "userType": "doctor"
    }
  }
}
```

**SAVE THE ACCESS TOKEN!** You'll need it for subsequent requests.

**Verify Session in Redis:**
```bash
redis-cli
KEYS session:*
GET session:<userId>
# Should show session data
EXIT
```

---

#### TEST 3: Create Patient ✅

```bash
# Replace YOUR_ACCESS_TOKEN with the token from login
curl -X POST http://localhost:3000/api/patients \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -d '{
    "firstName": "Jane",
    "lastName": "Doe",
    "dateOfBirth": "1990-05-15",
    "gender": "female",
    "bloodGroup": "O+",
    "phone": "+1987654321",
    "email": "jane.doe@example.com",
    "emergencyContactName": "John Doe",
    "emergencyContactPhone": "+1234567890",
    "emergencyContactRelationship": "spouse",
    "address": {
      "line1": "123 Main Street",
      "city": "New York",
      "state": "NY",
      "country": "USA",
      "postalCode": "10001"
    }
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Patient registered successfully",
  "data": {
    "id": "...",
    "mrn": "MRN-2024-000001",
    "first_name": "Jane",
    "last_name": "Doe",
    "age": 34
  }
}
```

**SAVE THE PATIENT ID!**

**Verify MRN Generation:**
```bash
psql -U hms_admin -d hospital_management -c "SELECT id, mrn, first_name, last_name, age FROM clinical.patients WHERE first_name='Jane';"
```

---

#### TEST 4: Add Life-Threatening Allergy (CRITICAL) ✅

```bash
# Replace PATIENT_ID and YOUR_ACCESS_TOKEN
curl -X POST http://localhost:3000/api/patients/PATIENT_ID/allergies \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -d '{
    "allergen": "Penicillin",
    "allergyType": "drug",
    "severity": "life_threatening",
    "reaction": "Anaphylaxis",
    "onsetDate": "2020-01-15",
    "notes": "Severe reaction requiring immediate medical attention"
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Allergy added successfully",
  "data": {
    "id": "...",
    "allergen": "Penicillin",
    "severity": "life_threatening"
  },
  "warning": "CRITICAL: Life-threatening allergy recorded"
}
```

**Verify Critical Alert Created:**
```bash
psql -U hms_admin -d hospital_management -c "SELECT * FROM clinical.critical_alerts WHERE alert_type='allergy' ORDER BY created_at DESC LIMIT 1;"
```

**Should show:**
- alert_type: 'allergy'
- severity: 'critical'
- alert_message: 'Life-threatening allergy added: Penicillin'

---

#### TEST 5: Create Doctor Schedule ✅

First, create a doctor in the database:
```bash
psql -U hms_admin -d hospital_management

INSERT INTO clinical.doctors (
  doctor_code, first_name, last_name, specialization, qualification,
  experience_years, phone, email, gender, date_of_birth, license_number,
  consultation_fee, department_id
) VALUES (
  'DOC-001', 'John', 'Smith', 'Cardiology', 'MD, FACC',
  15, '+1234567890', 'dr.smith@hospital.com', 'male', '1980-01-15',
  'MED-12345', 150.00, (SELECT id FROM core.departments LIMIT 1)
) RETURNING id;

-- SAVE THE DOCTOR ID!
\q
```

Now set the schedule:
```bash
# Replace DOCTOR_ID and YOUR_ACCESS_TOKEN
curl -X POST http://localhost:3000/api/doctors/DOCTOR_ID/schedule \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -d '{
    "dayOfWeek": "monday",
    "startTime": "09:00:00",
    "endTime": "17:00:00",
    "slotDuration": 30,
    "maxPatientsPerSlot": 1
  }'
```

---

#### TEST 6: Book Appointment with Conflict Detection (CRITICAL) ✅

```bash
# Replace PATIENT_ID, DOCTOR_ID, and YOUR_ACCESS_TOKEN
curl -X POST http://localhost:3000/api/appointments \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -d '{
    "patientId": "PATIENT_ID",
    "doctorId": "DOCTOR_ID",
    "appointmentDate": "2024-12-23",
    "appointmentTime": "10:00:00",
    "appointmentType": "consultation",
    "reason": "Regular checkup",
    "notes": "First visit"
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Appointment booked successfully",
  "data": {
    "id": "...",
    "appointment_number": "APT-2024-000001",
    "appointment_date": "2024-12-23",
    "appointment_time": "10:00:00",
    "status": "scheduled",
    "queuePosition": 1
  }
}
```

**Now try to book the SAME time slot (should fail):**
```bash
# Same request as above
curl -X POST http://localhost:3000/api/appointments \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -d '{
    "patientId": "PATIENT_ID",
    "doctorId": "DOCTOR_ID",
    "appointmentDate": "2024-12-23",
    "appointmentTime": "10:00:00",
    "appointmentType": "consultation",
    "reason": "Another checkup"
  }'
```

**Expected Response (ERROR):**
```json
{
  "success": false,
  "error": {
    "message": "Time slot fully booked",
    "code": "CONFLICT",
    "statusCode": 409
  }
}
```

**✅ CRITICAL: If this fails to prevent double-booking, DO NOT proceed to production!**

---

#### TEST 7: Check Available Time Slots ✅

```bash
# Replace DOCTOR_ID and YOUR_ACCESS_TOKEN
curl "http://localhost:3000/api/appointments/availability/DOCTOR_ID?date=2024-12-23" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

**Expected Response:**
```json
{
  "success": true,
  "data": {
    "available": true,
    "date": "2024-12-23",
    "slots": [
      {
        "time": "09:00:00",
        "available": true,
        "bookedCount": 0,
        "maxCapacity": 1
      },
      {
        "time": "09:30:00",
        "available": true,
        "bookedCount": 0,
        "maxCapacity": 1
      },
      {
        "time": "10:00:00",
        "available": false,
        "bookedCount": 1,
        "maxCapacity": 1
      }
    ]
  }
}
```

---

#### TEST 8: PHI Access Logging (HIPAA Compliance) ✅

```bash
# Check audit logs
psql -U hms_admin -d hospital_management -c "SELECT * FROM audit.phi_access_log ORDER BY accessed_at DESC LIMIT 10;"
```

**Should show:**
- user_id
- patient_id
- action (e.g., 'view_patient', 'add_allergy')
- ip_address
- accessed_at timestamp

**✅ CRITICAL: All PHI access must be logged!**

---

#### TEST 9: Account Lockout (Security) ✅

```bash
# Try 5 failed login attempts
for i in {1..5}; do
  curl -X POST http://localhost:3000/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{
      "username": "testdoctor",
      "password": "WrongPassword"
    }'
  echo "\nAttempt $i"
done

# 6th attempt should be locked
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testdoctor",
    "password": "SecurePass@123"
  }'
```

**Expected Response (after 5 failures):**
```json
{
  "success": false,
  "error": {
    "message": "Account locked due to too many failed attempts. Try again in 30 minutes.",
    "code": "ACCOUNT_LOCKED",
    "statusCode": 403
  }
}
```

---

### STEP 6: Verify Database Constraints (10 minutes)

```bash
psql -U hms_admin -d hospital_management
```

**Test 1: Unique Constraint**
```sql
-- Try to create duplicate user (should fail)
INSERT INTO core.users (username, email, password_hash, user_type)
VALUES ('testdoctor', 'duplicate@test.com', 'hash', 'doctor');
-- Should error: duplicate key value violates unique constraint
```

**Test 2: Foreign Key Constraint**
```sql
-- Try to create appointment with non-existent patient (should fail)
INSERT INTO clinical.appointments (patient_id, doctor_id, appointment_date, appointment_time, appointment_type, reason)
VALUES ('00000000-0000-0000-0000-000000000000', (SELECT id FROM clinical.doctors LIMIT 1), '2024-12-25', '10:00:00', 'consultation', 'test');
-- Should error: violates foreign key constraint
```

**Test 3: Check Constraint**
```sql
-- Try to insert invalid blood group (should fail)
INSERT INTO clinical.patients (first_name, last_name, date_of_birth, gender, blood_group, phone, emergency_contact_name, emergency_contact_phone, emergency_contact_relationship)
VALUES ('Test', 'Patient', '1990-01-01', 'male', 'INVALID', '+1234567890', 'Emergency', '+0987654321', 'friend');
-- Should error: violates check constraint
```

**Test 4: Trigger (updated_at)**
```sql
-- Update a patient
UPDATE clinical.patients SET phone = '+9999999999' WHERE first_name = 'Jane';

-- Check updated_at changed
SELECT first_name, phone, created_at, updated_at FROM clinical.patients WHERE first_name = 'Jane';
-- updated_at should be more recent than created_at
```

**Exit:**
```sql
\q
```

---

## ✅ Testing Results Summary

### Critical Tests Passed:
- [ ] Database schemas executed successfully
- [ ] All 53 tables created
- [ ] User registration works
- [ ] Login with JWT works
- [ ] Patient creation with MRN generation works
- [ ] Life-threatening allergy creates critical alert
- [ ] Appointment booking works
- [ ] **CRITICAL:** Double-booking prevention works
- [ ] PHI access logging works
- [ ] Account lockout works
- [ ] Database constraints work
- [ ] Triggers work

### Issues Found:
(Document any issues here)

---

## 🚨 Critical Failures (DO NOT PROCEED if any fail)

1. **Double-booking prevention fails** - STOP
2. **Critical alerts not generated** - STOP
3. **PHI access not logged** - STOP
4. **Database constraints not working** - STOP
5. **Authentication bypass possible** - STOP

---

## 📊 Performance Baseline

Record these metrics for future comparison:

```bash
# Database size
psql -U hms_admin -d hospital_management -c "SELECT pg_size_pretty(pg_database_size('hospital_management'));"

# Table counts
psql -U hms_admin -d hospital_management -c "SELECT schemaname, COUNT(*) FROM pg_tables WHERE schemaname IN ('core', 'clinical', 'billing', 'inventory', 'emergency') GROUP BY schemaname;"

# Index count
psql -U hms_admin -d hospital_management -c "SELECT COUNT(*) FROM pg_indexes WHERE schemaname IN ('core', 'clinical', 'billing', 'inventory', 'emergency');"
```

---

## ✅ Sign-Off

**Tester Name:** _______________  
**Date:** _______________  
**All Critical Tests Passed:** [ ] Yes [ ] No  
**Ready for Next Phase:** [ ] Yes [ ] No  

**Notes:**
_______________________________________
_______________________________________
_______________________________________

---

**Next Steps After Testing:**
1. Document any issues found
2. Fix critical issues
3. Re-test failed scenarios
4. Proceed to build remaining services
5. Implement frontend
6. Conduct full integration testing
