# 🚀 Hospital Management System - Quick Start Guide

## ⚠️ CRITICAL NOTICE
This is a **LIFE-CRITICAL healthcare system**. Follow all steps carefully and ensure proper testing before any production use.

---

## 📋 Prerequisites

### Required Software:
- **Node.js** 18+ ([Download](https://nodejs.org/))
- **PostgreSQL** 14+ ([Download](https://www.postgresql.org/download/))
- **Redis** 6+ ([Download](https://redis.io/download))
- **Git** ([Download](https://git-scm.com/downloads))

### Optional (Recommended):
- **Docker** & **Docker Compose** ([Download](https://www.docker.com/))
- **pgAdmin** or **DBeaver** (Database GUI)
- **Postman** or **Insomnia** (API testing)

---

## 🎯 Quick Start (5 Minutes)

### Option A: Using Docker (Recommended)

```bash
# 1. Navigate to project
cd hospital-management-system

# 2. Create environment file
cp .env.example .env

# 3. Edit .env and set your passwords
# (Use a text editor to update DB_PASSWORD, REDIS_PASSWORD, JWT_SECRET)

# 4. Start all services
docker-compose up -d

# 5. Check if services are running
docker-compose ps

# 6. View logs
docker-compose logs -f
```

**Services will be available at:**
- API Gateway: http://localhost:3000
- Auth Service: http://localhost:3001
- Patient Service: http://localhost:3002
- PostgreSQL: localhost:5432
- Redis: localhost:6379

---

### Option B: Manual Setup

#### Step 1: Install Dependencies

```bash
# Install root dependencies
npm install

# Install backend dependencies
cd backend
npm install
cd ..
```

#### Step 2: Setup PostgreSQL

```bash
# Create database
createdb hospital_management

# Create user
psql -c "CREATE USER hms_admin WITH ENCRYPTED PASSWORD 'your_secure_password';"
psql -c "GRANT ALL PRIVILEGES ON DATABASE hospital_management TO hms_admin;"

# Execute database schemas (IN ORDER - IMPORTANT!)
psql -U hms_admin -d hospital_management -f database/schemas/001_core_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/002_clinical_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/003_appointments_consultations_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/004_laboratory_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/005_pharmacy_inventory_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/006_billing_insurance_schema.sql
psql -U hms_admin -d hospital_management -f database/schemas/007_emergency_icu_schema.sql
```

#### Step 3: Setup Redis

```bash
# Start Redis server
redis-server

# In another terminal, verify Redis is running
redis-cli ping
# Should return: PONG
```

#### Step 4: Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env file with your settings
# IMPORTANT: Change these values!
# - DB_PASSWORD
# - REDIS_PASSWORD
# - JWT_SECRET
# - JWT_REFRESH_SECRET
```

#### Step 5: Start Services

```bash
# Terminal 1: Auth Service
cd backend/services/auth-service
npm run dev

# Terminal 2: API Gateway
cd backend/api-gateway
npm run dev

# Terminal 3: Patient Service
cd backend/services/patient-service
npm run dev

# Terminal 4: Doctor Service
cd backend/services/doctor-service
npm run dev
```

---

## 🧪 Testing the System

### 1. Health Check

```bash
# Check API Gateway
curl http://localhost:3000/health

# Check Auth Service
curl http://localhost:3001/health

# Check Patient Service
curl http://localhost:3002/health
```

### 2. Register a User

```bash
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "Test@1234",
    "userType": "patient",
    "firstName": "John",
    "lastName": "Doe",
    "phone": "+1234567890",
    "dateOfBirth": "1990-01-01",
    "gender": "male"
  }'
```

### 3. Login

```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "Test@1234"
  }'
```

**Save the `accessToken` from the response!**

### 4. Create a Patient

```bash
curl -X POST http://localhost:3000/api/patients \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -d '{
    "firstName": "Jane",
    "lastName": "Smith",
    "dateOfBirth": "1985-05-15",
    "gender": "female",
    "bloodGroup": "O+",
    "phone": "+1987654321",
    "email": "jane.smith@example.com",
    "emergencyContactName": "John Smith",
    "emergencyContactPhone": "+1234567890",
    "emergencyContactRelationship": "spouse",
    "address": {
      "line1": "123 Main St",
      "city": "New York",
      "state": "NY",
      "country": "USA",
      "postalCode": "10001"
    }
  }'
```

---

## 📊 Verify Database

```bash
# Connect to PostgreSQL
psql -U hms_admin -d hospital_management

# Check tables
\dt clinical.*
\dt core.*
\dt billing.*
\dt inventory.*

# Check a specific table
SELECT * FROM core.users LIMIT 5;
SELECT * FROM clinical.patients LIMIT 5;

# Exit
\q
```

---

## 🔧 Troubleshooting

### Issue: "Cannot connect to PostgreSQL"

**Solution:**
```bash
# Check if PostgreSQL is running
pg_isready

# Start PostgreSQL (varies by OS)
# macOS: brew services start postgresql
# Linux: sudo systemctl start postgresql
# Windows: Start from Services

# Check connection
psql -U hms_admin -d hospital_management -c "SELECT 1;"
```

### Issue: "Cannot connect to Redis"

**Solution:**
```bash
# Check if Redis is running
redis-cli ping

# Start Redis
redis-server

# Or with Docker
docker run -d -p 6379:6379 redis:7-alpine
```

### Issue: "Port already in use"

**Solution:**
```bash
# Find process using port (example: 3000)
# macOS/Linux:
lsof -i :3000

# Windows:
netstat -ano | findstr :3000

# Kill the process or change port in .env
```

### Issue: "Module not found"

**Solution:**
```bash
# Reinstall dependencies
rm -rf node_modules package-lock.json
npm install

# For backend
cd backend
rm -rf node_modules package-lock.json
npm install
```

### Issue: "Database schema errors"

**Solution:**
```bash
# Drop and recreate database
dropdb hospital_management
createdb hospital_management

# Re-execute schemas IN ORDER
psql -U hms_admin -d hospital_management -f database/schemas/001_core_schema.sql
# ... continue with 002-007
```

---

## 🔐 Security Checklist

Before deploying to production:

- [ ] Change all default passwords in .env
- [ ] Generate secure JWT secrets (256-bit minimum)
- [ ] Enable SSL/TLS for all connections
- [ ] Set up firewall rules
- [ ] Enable database encryption at rest
- [ ] Configure automated backups
- [ ] Set up monitoring and alerting
- [ ] Perform security audit
- [ ] Conduct penetration testing
- [ ] Review and update CORS settings
- [ ] Enable rate limiting on all endpoints
- [ ] Set up log rotation
- [ ] Configure session timeouts
- [ ] Enable MFA for all admin accounts
- [ ] Review and restrict database permissions

---

## 📚 Next Steps

1. **Read the Documentation:**
   - `README.md` - Project overview
   - `IMPLEMENTATION_SUMMARY.md` - What's been built
   - `hospital-management-system-docs/` - Detailed documentation

2. **Explore the API:**
   - Import Postman collection (if available)
   - Test all endpoints
   - Review API responses

3. **Customize:**
   - Add your hospital's branding
   - Configure email/SMS providers
   - Set up payment gateways
   - Integrate with existing systems

4. **Deploy:**
   - Set up production environment
   - Configure CI/CD pipeline
   - Set up monitoring (Prometheus, Grafana)
   - Configure logging (ELK stack)

---

## 🆘 Getting Help

### Common Commands:

```bash
# View all running services
docker-compose ps

# View logs for specific service
docker-compose logs -f auth-service

# Restart a service
docker-compose restart auth-service

# Stop all services
docker-compose down

# Stop and remove volumes (⚠️ DELETES DATA)
docker-compose down -v

# Check database connection
npm run db:test

# Run migrations
npm run db:migrate

# Seed database with test data
npm run db:seed
```

### Useful Database Queries:

```sql
-- Check system health
SELECT COUNT(*) FROM core.users;
SELECT COUNT(*) FROM clinical.patients;
SELECT COUNT(*) FROM clinical.appointments;

-- View recent activity
SELECT * FROM audit.audit_log ORDER BY created_at DESC LIMIT 10;

-- Check active sessions
SELECT * FROM core.sessions WHERE is_active = true;

-- View critical alerts
SELECT * FROM clinical.critical_alerts WHERE is_resolved = false;
```

---

## 📞 Support

For issues or questions:
1. Check the documentation in `hospital-management-system-docs/`
2. Review `TECHNICAL_CHALLENGES.md` for common issues
3. Check the TODO.md for known limitations
4. Review error logs in the console

---

## ⚠️ Important Reminders

1. **This is a LIFE-CRITICAL system** - Test thoroughly before production use
2. **HIPAA Compliance** - Ensure all PHI is properly protected
3. **Regular Backups** - Set up automated backups immediately
4. **Security Updates** - Keep all dependencies up to date
5. **Monitoring** - Set up 24/7 monitoring and alerting
6. **Incident Response** - Have a plan for system failures
7. **Staff Training** - Train all users before go-live
8. **Data Validation** - Verify all data entry is accurate
9. **Audit Logs** - Review audit logs regularly
10. **Disaster Recovery** - Test your backup and recovery procedures

---

**System Status:** ✅ Ready for Development/Testing  
**Production Ready:** ⚠️ Requires additional services and testing  
**Completion:** ~15% of total project  

**Good luck building a system that saves lives! 🏥**
