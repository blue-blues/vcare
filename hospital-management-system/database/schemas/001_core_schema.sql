-- ============================================
-- HOSPITAL MANAGEMENT SYSTEM - CORE SCHEMA
-- ============================================
-- ⚠️ CRITICAL: This schema handles sensitive patient data
-- HIPAA Compliance Required
-- All changes must be audited

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================
-- SCHEMA CREATION
-- ============================================

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS clinical;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS audit;

-- Set search path
SET search_path TO core, clinical, billing, inventory, audit, public;

-- ============================================
-- CUSTOM TYPES
-- ============================================

-- User types
CREATE TYPE user_type_enum AS ENUM (
    'patient',
    'doctor',
    'nurse',
    'admin',
    'receptionist',
    'pharmacist',
    'lab_technician',
    'radiologist',
    'staff'
);

-- Gender
CREATE TYPE gender_enum AS ENUM ('male', 'female', 'other', 'prefer_not_to_say');

-- Blood groups
CREATE TYPE blood_group_enum AS ENUM ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-');

-- Marital status
CREATE TYPE marital_status_enum AS ENUM ('single', 'married', 'divorced', 'widowed', 'separated');

-- Appointment status
CREATE TYPE appointment_status_enum AS ENUM (
    'scheduled',
    'confirmed',
    'checked_in',
    'in_progress',
    'completed',
    'cancelled',
    'no_show',
    'rescheduled'
);

-- Appointment type
CREATE TYPE appointment_type_enum AS ENUM (
    'consultation',
    'follow_up',
    'procedure',
    'emergency',
    'telemedicine',
    'vaccination',
    'checkup'
);

-- Priority levels
CREATE TYPE priority_enum AS ENUM ('low', 'normal', 'high', 'urgent', 'emergency', 'critical');

-- Status types
CREATE TYPE status_enum AS ENUM ('active', 'inactive', 'pending', 'completed', 'cancelled', 'suspended');

-- ============================================
-- CORE TABLES - USERS & AUTHENTICATION
-- ============================================

-- Users table (base for all user types)
CREATE TABLE core.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    user_type user_type_enum NOT NULL,
    
    -- Account status
    is_active BOOLEAN DEFAULT true NOT NULL,
    is_verified BOOLEAN DEFAULT false NOT NULL,
    is_locked BOOLEAN DEFAULT false NOT NULL,
    
    -- Security
    two_factor_enabled BOOLEAN DEFAULT false NOT NULL,
    two_factor_secret VARCHAR(255),
    failed_login_attempts INTEGER DEFAULT 0 NOT NULL,
    locked_until TIMESTAMP,
    last_login TIMESTAMP,
    last_password_change TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    password_reset_token VARCHAR(255),
    password_reset_expires TIMESTAMP,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    updated_by UUID REFERENCES core.users(id),
    deleted_at TIMESTAMP,
    
    -- Constraints
    CONSTRAINT check_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT check_username_length CHECK (LENGTH(username) >= 3),
    CONSTRAINT check_failed_attempts CHECK (failed_login_attempts >= 0)
);

-- Indexes for users
CREATE INDEX idx_users_email ON core.users(email);
CREATE INDEX idx_users_username ON core.users(username);
CREATE INDEX idx_users_user_type ON core.users(user_type);
CREATE INDEX idx_users_is_active ON core.users(is_active);
CREATE INDEX idx_users_created_at ON core.users(created_at);

-- Roles table
CREATE TABLE core.roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    is_system BOOLEAN DEFAULT false NOT NULL,
    is_active BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_role_name CHECK (LENGTH(name) >= 2)
);

-- Permissions table
CREATE TABLE core.permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    resource VARCHAR(100) NOT NULL,
    action VARCHAR(50) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT unique_resource_action UNIQUE(resource, action)
);

-- Role permissions (many-to-many)
CREATE TABLE core.role_permissions (
    role_id UUID REFERENCES core.roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES core.permissions(id) ON DELETE CASCADE,
    granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    granted_by UUID REFERENCES core.users(id),
    
    PRIMARY KEY (role_id, permission_id)
);

-- User roles (many-to-many)
CREATE TABLE core.user_roles (
    user_id UUID REFERENCES core.users(id) ON DELETE CASCADE,
    role_id UUID REFERENCES core.roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    assigned_by UUID REFERENCES core.users(id),
    expires_at TIMESTAMP,
    
    PRIMARY KEY (user_id, role_id)
);

-- Sessions table
CREATE TABLE core.sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES core.users(id) ON DELETE CASCADE NOT NULL,
    token VARCHAR(500) UNIQUE NOT NULL,
    refresh_token VARCHAR(500) UNIQUE,
    ip_address INET,
    user_agent TEXT,
    device_info JSONB,
    is_active BOOLEAN DEFAULT true NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_expires_future CHECK (expires_at > created_at)
);

CREATE INDEX idx_sessions_user_id ON core.sessions(user_id);
CREATE INDEX idx_sessions_token ON core.sessions(token);
CREATE INDEX idx_sessions_expires_at ON core.sessions(expires_at);

-- ============================================
-- AUDIT LOGGING (CRITICAL FOR HIPAA)
-- ============================================

CREATE TABLE audit.audit_log (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    action VARCHAR(20) NOT NULL, -- INSERT, UPDATE, DELETE, SELECT
    user_id UUID REFERENCES core.users(id),
    
    -- Change tracking
    old_values JSONB,
    new_values JSONB,
    changed_fields TEXT[],
    
    -- Request context
    ip_address INET,
    user_agent TEXT,
    request_id UUID,
    session_id UUID,
    
    -- PHI access tracking (HIPAA requirement)
    is_phi_access BOOLEAN DEFAULT false,
    access_reason TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_action CHECK (action IN ('INSERT', 'UPDATE', 'DELETE', 'SELECT', 'EXPORT'))
);

-- Indexes for audit log (critical for performance)
CREATE INDEX idx_audit_log_table_record ON audit.audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_user_id ON audit.audit_log(user_id);
CREATE INDEX idx_audit_log_created_at ON audit.audit_log(created_at);
CREATE INDEX idx_audit_log_action ON audit.audit_log(action);
CREATE INDEX idx_audit_log_is_phi ON audit.audit_log(is_phi_access);

-- Security events log
CREATE TABLE audit.security_events (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL, -- LOW, MEDIUM, HIGH, CRITICAL
    user_id UUID REFERENCES core.users(id),
    ip_address INET,
    user_agent TEXT,
    description TEXT NOT NULL,
    metadata JSONB,
    is_resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMP,
    resolved_by UUID REFERENCES core.users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_severity CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL'))
);

CREATE INDEX idx_security_events_type ON audit.security_events(event_type);
CREATE INDEX idx_security_events_severity ON audit.security_events(severity);
CREATE INDEX idx_security_events_created_at ON audit.security_events(created_at);
CREATE INDEX idx_security_events_user_id ON audit.security_events(user_id);

-- ============================================
-- DEPARTMENTS
-- ============================================

CREATE TABLE core.departments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) UNIQUE NOT NULL,
    code VARCHAR(20) UNIQUE NOT NULL,
    description TEXT,
    head_doctor_id UUID,
    
    -- Location
    floor_number INTEGER,
    building VARCHAR(50),
    extension_number VARCHAR(20),
    
    -- Status
    is_emergency BOOLEAN DEFAULT false NOT NULL,
    is_active BOOLEAN DEFAULT true NOT NULL,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_floor_positive CHECK (floor_number > 0)
);

CREATE INDEX idx_departments_code ON core.departments(code);
CREATE INDEX idx_departments_is_active ON core.departments(is_active);

-- ============================================
-- TRIGGER FUNCTIONS
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION core.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to log changes to audit table
CREATE OR REPLACE FUNCTION audit.log_changes()
RETURNS TRIGGER AS $$
DECLARE
    old_data JSONB;
    new_data JSONB;
    changed_fields TEXT[];
BEGIN
    -- Convert OLD and NEW to JSONB
    IF TG_OP = 'DELETE' THEN
        old_data := to_jsonb(OLD);
        new_data := NULL;
    ELSIF TG_OP = 'UPDATE' THEN
        old_data := to_jsonb(OLD);
        new_data := to_jsonb(NEW);
        
        -- Identify changed fields
        SELECT array_agg(key)
        INTO changed_fields
        FROM jsonb_each(old_data)
        WHERE old_data->key IS DISTINCT FROM new_data->key;
    ELSIF TG_OP = 'INSERT' THEN
        old_data := NULL;
        new_data := to_jsonb(NEW);
    END IF;
    
    -- Insert audit record
    INSERT INTO audit.audit_log (
        table_name,
        record_id,
        action,
        user_id,
        old_values,
        new_values,
        changed_fields,
        ip_address,
        session_id
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        current_setting('app.current_user_id', true)::UUID,
        old_data,
        new_data,
        changed_fields,
        inet_client_addr(),
        current_setting('app.session_id', true)::UUID
    );
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- APPLY TRIGGERS
-- ============================================

-- Updated_at triggers
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON core.users
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_roles_updated_at
    BEFORE UPDATE ON core.roles
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_departments_updated_at
    BEFORE UPDATE ON core.departments
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

-- Audit triggers for users table (CRITICAL)
CREATE TRIGGER audit_users_changes
    AFTER INSERT OR UPDATE OR DELETE ON core.users
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

-- ============================================
-- INITIAL DATA - SYSTEM ROLES
-- ============================================

INSERT INTO core.roles (name, description, is_system) VALUES
    ('super_admin', 'Super Administrator with full system access', true),
    ('admin', 'System Administrator', true),
    ('doctor', 'Medical Doctor', true),
    ('nurse', 'Registered Nurse', true),
    ('receptionist', 'Front Desk Receptionist', true),
    ('pharmacist', 'Pharmacy Staff', true),
    ('lab_technician', 'Laboratory Technician', true),
    ('radiologist', 'Radiology Specialist', true),
    ('billing_staff', 'Billing Department Staff', true),
    ('patient', 'Patient User', true);

-- ============================================
-- INITIAL DATA - SYSTEM PERMISSIONS
-- ============================================

INSERT INTO core.permissions (resource, action, description) VALUES
    -- System permissions
    ('system', 'manage', 'Full system management'),
    ('system', 'configure', 'System configuration'),
    ('system', 'view_logs', 'View system logs'),
    
    -- User management
    ('users', 'create', 'Create new users'),
    ('users', 'read', 'View user information'),
    ('users', 'update', 'Update user information'),
    ('users', 'delete', 'Delete users'),
    ('users', 'manage_roles', 'Manage user roles'),
    
    -- Patient management
    ('patients', 'create', 'Register new patients'),
    ('patients', 'read', 'View patient information'),
    ('patients', 'read_medical', 'View medical records'),
    ('patients', 'update', 'Update patient information'),
    ('patients', 'update_medical', 'Update medical records'),
    ('patients', 'delete', 'Delete patient records'),
    
    -- Appointments
    ('appointments', 'create', 'Book appointments'),
    ('appointments', 'read', 'View appointments'),
    ('appointments', 'update', 'Modify appointments'),
    ('appointments', 'cancel', 'Cancel appointments'),
    
    -- Prescriptions
    ('prescriptions', 'create', 'Write prescriptions'),
    ('prescriptions', 'read', 'View prescriptions'),
    ('prescriptions', 'update', 'Modify prescriptions'),
    ('prescriptions', 'dispense', 'Dispense medications'),
    
    -- Lab tests
    ('lab_tests', 'order', 'Order lab tests'),
    ('lab_tests', 'read', 'View lab results'),
    ('lab_tests', 'update', 'Update lab results'),
    ('lab_tests', 'verify', 'Verify lab results'),
    
    -- Billing
    ('billing', 'create', 'Create bills'),
    ('billing', 'read', 'View billing information'),
    ('billing', 'update', 'Update bills'),
    ('billing', 'process_payment', 'Process payments'),
    
    -- Reports
    ('reports', 'generate', 'Generate reports'),
    ('reports', 'export', 'Export reports'),
    
    -- Audit
    ('audit', 'view', 'View audit logs');

-- ============================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================

COMMENT ON SCHEMA core IS 'Core system tables for users, roles, and authentication';
COMMENT ON SCHEMA clinical IS 'Clinical data including patients, appointments, consultations';
COMMENT ON SCHEMA billing IS 'Billing and financial data';
COMMENT ON SCHEMA inventory IS 'Pharmacy and medical inventory';
COMMENT ON SCHEMA audit IS 'Audit logs and security events (HIPAA compliance)';

COMMENT ON TABLE core.users IS 'Base user table for all system users - CRITICAL: Contains authentication data';
COMMENT ON TABLE audit.audit_log IS 'HIPAA-compliant audit trail - NEVER DELETE';
COMMENT ON TABLE audit.security_events IS 'Security event tracking for threat detection';

-- ============================================
-- GRANT PERMISSIONS (Principle of Least Privilege)
-- ============================================

-- Revoke all default permissions
REVOKE ALL ON ALL TABLES IN SCHEMA core, clinical, billing, inventory, audit FROM PUBLIC;

-- Grant specific permissions (to be configured per deployment)
-- GRANT SELECT, INSERT, UPDATE ON core.users TO hms_app_user;
-- GRANT SELECT ON audit.audit_log TO hms_audit_viewer;

-- ============================================
-- SCHEMA VERSION TRACKING
-- ============================================

CREATE TABLE core.schema_versions (
    id SERIAL PRIMARY KEY,
    version VARCHAR(20) NOT NULL,
    description TEXT,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);

INSERT INTO core.schema_versions (version, description) VALUES
    ('1.0.0', 'Initial core schema with users, roles, permissions, and audit logging');

-- ============================================
-- END OF CORE SCHEMA
-- ============================================
