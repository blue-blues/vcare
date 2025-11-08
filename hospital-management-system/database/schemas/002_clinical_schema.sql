-- ============================================
-- HOSPITAL MANAGEMENT SYSTEM - CLINICAL SCHEMA
-- ============================================
-- ⚠️ CRITICAL: Contains Protected Health Information (PHI)
-- HIPAA Compliance Required - All access must be audited

SET search_path TO clinical, core, audit, public;

-- ============================================
-- PATIENTS
-- ============================================

CREATE TABLE clinical.patients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE REFERENCES core.users(id) ON DELETE CASCADE,
    
    -- Patient Identification
    patient_number VARCHAR(20) UNIQUE NOT NULL,
    medical_record_number VARCHAR(20) UNIQUE,
    
    -- Personal Information (PHI)
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender gender_enum NOT NULL,
    blood_group blood_group_enum,
    marital_status marital_status_enum,
    
    -- Demographics
    occupation VARCHAR(100),
    nationality VARCHAR(100),
    religion VARCHAR(50),
    language_preference VARCHAR(50) DEFAULT 'English',
    
    -- Contact Information (PHI)
    phone_primary VARCHAR(20) NOT NULL,
    phone_secondary VARCHAR(20),
    email VARCHAR(255),
    
    -- Address (PHI)
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    city VARCHAR(100),
    state VARCHAR(100),
    country VARCHAR(100) DEFAULT 'USA',
    postal_code VARCHAR(20),
    
    -- Emergency Contact (PHI)
    emergency_contact_name VARCHAR(200),
    emergency_contact_relationship VARCHAR(50),
    emergency_contact_phone VARCHAR(20),
    emergency_contact_email VARCHAR(255),
    
    -- Medical Information
    allergies TEXT[],
    chronic_conditions TEXT[],
    current_medications TEXT[],
    
    -- Biometric Data (Encrypted)
    photo_url VARCHAR(500),
    fingerprint_data BYTEA,
    
    -- Insurance
    primary_insurance_id UUID,
    secondary_insurance_id UUID,
    
    -- Status
    is_vip BOOLEAN DEFAULT false NOT NULL,
    is_blacklisted BOOLEAN DEFAULT false NOT NULL,
    blacklist_reason TEXT,
    is_deceased BOOLEAN DEFAULT false NOT NULL,
    date_of_death DATE,
    
    -- Statistics
    registration_date DATE DEFAULT CURRENT_DATE NOT NULL,
    last_visit_date DATE,
    total_visits INTEGER DEFAULT 0 NOT NULL,
    total_admissions INTEGER DEFAULT 0 NOT NULL,
    
    -- Notes
    notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    updated_by UUID REFERENCES core.users(id),
    deleted_at TIMESTAMP,
    
    -- Constraints
    CONSTRAINT check_age CHECK (date_of_birth <= CURRENT_DATE),
    CONSTRAINT check_death_after_birth CHECK (date_of_death IS NULL OR date_of_death >= date_of_birth),
    CONSTRAINT check_phone_format CHECK (phone_primary ~ '^[0-9+\-() ]+$'),
    CONSTRAINT check_visits CHECK (total_visits >= 0),
    CONSTRAINT check_admissions CHECK (total_admissions >= 0)
);

-- Indexes for patients
CREATE INDEX idx_patients_user_id ON clinical.patients(user_id);
CREATE INDEX idx_patients_patient_number ON clinical.patients(patient_number);
CREATE INDEX idx_patients_name ON clinical.patients(last_name, first_name);
CREATE INDEX idx_patients_dob ON clinical.patients(date_of_birth);
CREATE INDEX idx_patients_phone ON clinical.patients(phone_primary);
CREATE INDEX idx_patients_email ON clinical.patients(email);
CREATE INDEX idx_patients_registration_date ON clinical.patients(registration_date);
CREATE INDEX idx_patients_is_deceased ON clinical.patients(is_deceased);

-- Full-text search on patient names
CREATE INDEX idx_patients_name_trgm ON clinical.patients USING gin(
    (first_name || ' ' || last_name) gin_trgm_ops
);

-- ============================================
-- PATIENT MEDICAL HISTORY
-- ============================================

CREATE TABLE clinical.medical_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    
    -- Condition Information
    condition_name VARCHAR(255) NOT NULL,
    icd_10_code VARCHAR(20),
    snomed_code VARCHAR(50),
    
    -- Timeline
    diagnosed_date DATE,
    resolved_date DATE,
    
    -- Classification
    is_chronic BOOLEAN DEFAULT false NOT NULL,
    is_hereditary BOOLEAN DEFAULT false NOT NULL,
    severity priority_enum DEFAULT 'normal',
    
    -- Details
    symptoms TEXT,
    treatment_received TEXT,
    notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_dates CHECK (resolved_date IS NULL OR resolved_date >= diagnosed_date)
);

CREATE INDEX idx_medical_history_patient ON clinical.medical_history(patient_id);
CREATE INDEX idx_medical_history_condition ON clinical.medical_history(condition_name);
CREATE INDEX idx_medical_history_icd ON clinical.medical_history(icd_10_code);

-- ============================================
-- PATIENT ALLERGIES
-- ============================================

CREATE TYPE allergen_type_enum AS ENUM ('drug', 'food', 'environmental', 'latex', 'other');
CREATE TYPE allergy_severity_enum AS ENUM ('mild', 'moderate', 'severe', 'life_threatening');

CREATE TABLE clinical.patient_allergies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    
    -- Allergen Information
    allergen_type allergen_type_enum NOT NULL,
    allergen_name VARCHAR(255) NOT NULL,
    allergen_code VARCHAR(50), -- RxNorm or SNOMED code
    
    -- Reaction Details
    reaction_type VARCHAR(255),
    symptoms TEXT[],
    severity allergy_severity_enum NOT NULL,
    
    -- Timeline
    onset_date DATE,
    last_reaction_date DATE,
    
    -- Status
    is_active BOOLEAN DEFAULT true NOT NULL,
    verified_by UUID REFERENCES core.users(id),
    verified_at TIMESTAMP,
    
    -- Notes
    notes TEXT,
    treatment_notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT unique_patient_allergen UNIQUE(patient_id, allergen_name, allergen_type)
);

CREATE INDEX idx_allergies_patient ON clinical.patient_allergies(patient_id);
CREATE INDEX idx_allergies_type ON clinical.patient_allergies(allergen_type);
CREATE INDEX idx_allergies_severity ON clinical.patient_allergies(severity);
CREATE INDEX idx_allergies_active ON clinical.patient_allergies(is_active);

-- ============================================
-- FAMILY MEDICAL HISTORY
-- ============================================

CREATE TYPE family_relationship_enum AS ENUM (
    'father', 'mother', 'brother', 'sister', 
    'son', 'daughter', 'grandfather', 'grandmother',
    'uncle', 'aunt', 'cousin', 'other'
);

CREATE TABLE clinical.family_medical_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    
    -- Relative Information
    relationship family_relationship_enum NOT NULL,
    relative_name VARCHAR(255),
    
    -- Medical Condition
    condition_name VARCHAR(255) NOT NULL,
    icd_10_code VARCHAR(20),
    age_at_diagnosis INTEGER,
    
    -- Status
    is_deceased BOOLEAN DEFAULT false NOT NULL,
    age_at_death INTEGER,
    cause_of_death VARCHAR(255),
    
    -- Notes
    notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_age_diagnosis CHECK (age_at_diagnosis > 0 AND age_at_diagnosis < 150),
    CONSTRAINT check_age_death CHECK (age_at_death IS NULL OR (age_at_death > 0 AND age_at_death < 150))
);

CREATE INDEX idx_family_history_patient ON clinical.family_medical_history(patient_id);
CREATE INDEX idx_family_history_condition ON clinical.family_medical_history(condition_name);

-- ============================================
-- PATIENT INSURANCE
-- ============================================

CREATE TYPE insurance_coverage_enum AS ENUM ('basic', 'standard', 'premium', 'comprehensive');
CREATE TYPE verification_status_enum AS ENUM ('pending', 'verified', 'rejected', 'expired');

CREATE TABLE clinical.patient_insurance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    
    -- Insurance Provider
    insurance_provider VARCHAR(255) NOT NULL,
    provider_code VARCHAR(50),
    policy_number VARCHAR(100) UNIQUE NOT NULL,
    group_number VARCHAR(100),
    
    -- Policy Holder
    policy_holder_name VARCHAR(255) NOT NULL,
    policy_holder_relationship VARCHAR(50),
    policy_holder_dob DATE,
    
    -- Coverage Details
    coverage_type insurance_coverage_enum NOT NULL,
    coverage_amount DECIMAL(12, 2),
    copay_percentage DECIMAL(5, 2),
    deductible DECIMAL(10, 2),
    out_of_pocket_max DECIMAL(10, 2),
    
    -- Validity
    valid_from DATE NOT NULL,
    valid_until DATE NOT NULL,
    
    -- Status
    is_primary BOOLEAN DEFAULT true NOT NULL,
    is_active BOOLEAN DEFAULT true NOT NULL,
    verification_status verification_status_enum DEFAULT 'pending',
    verification_date TIMESTAMP,
    verified_by UUID REFERENCES core.users(id),
    
    -- Contact
    provider_phone VARCHAR(20),
    provider_email VARCHAR(255),
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_validity_dates CHECK (valid_until > valid_from),
    CONSTRAINT check_copay CHECK (copay_percentage >= 0 AND copay_percentage <= 100)
);

CREATE INDEX idx_insurance_patient ON clinical.patient_insurance(patient_id);
CREATE INDEX idx_insurance_policy ON clinical.patient_insurance(policy_number);
CREATE INDEX idx_insurance_provider ON clinical.patient_insurance(insurance_provider);
CREATE INDEX idx_insurance_active ON clinical.patient_insurance(is_active);

-- ============================================
-- DOCTORS
-- ============================================

CREATE TABLE clinical.doctors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE REFERENCES core.users(id) ON DELETE CASCADE NOT NULL,
    
    -- Identification
    employee_id VARCHAR(20) UNIQUE NOT NULL,
    
    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE,
    gender gender_enum NOT NULL,
    
    -- Professional Information
    medical_license_number VARCHAR(50) UNIQUE NOT NULL,
    medical_license_state VARCHAR(50),
    medical_license_expiry DATE NOT NULL,
    dea_number VARCHAR(20), -- Drug Enforcement Administration number
    npi_number VARCHAR(20), -- National Provider Identifier
    
    -- Specialization
    specialization VARCHAR(100) NOT NULL,
    sub_specialization VARCHAR(100),
    board_certifications TEXT[],
    qualifications TEXT[] NOT NULL,
    years_of_experience INTEGER DEFAULT 0,
    
    -- Department and Position
    department_id UUID REFERENCES core.departments(id),
    designation VARCHAR(100),
    is_consultant BOOLEAN DEFAULT false NOT NULL,
    is_surgeon BOOLEAN DEFAULT false NOT NULL,
    is_head_of_department BOOLEAN DEFAULT false NOT NULL,
    
    -- Contact Information
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(255) NOT NULL,
    office_room VARCHAR(50),
    office_extension VARCHAR(20),
    
    -- Consultation Details
    consultation_fee DECIMAL(10, 2),
    consultation_duration_minutes INTEGER DEFAULT 30,
    max_daily_appointments INTEGER DEFAULT 20,
    
    -- Availability
    is_available BOOLEAN DEFAULT true NOT NULL,
    is_accepting_new_patients BOOLEAN DEFAULT true NOT NULL,
    
    -- Performance Metrics
    rating DECIMAL(3, 2) DEFAULT 0.00,
    total_reviews INTEGER DEFAULT 0,
    total_patients_treated INTEGER DEFAULT 0,
    total_surgeries INTEGER DEFAULT 0,
    
    -- Employment
    joining_date DATE NOT NULL,
    resignation_date DATE,
    employment_status status_enum DEFAULT 'active',
    
    -- Media
    photo_url VARCHAR(500),
    digital_signature BYTEA,
    
    -- Biography
    biography TEXT,
    languages_spoken TEXT[],
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_rating CHECK (rating >= 0 AND rating <= 5),
    CONSTRAINT check_license_valid CHECK (medical_license_expiry > CURRENT_DATE),
    CONSTRAINT check_experience CHECK (years_of_experience >= 0),
    CONSTRAINT check_consultation_fee CHECK (consultation_fee >= 0),
    CONSTRAINT check_max_appointments CHECK (max_daily_appointments > 0)
);

-- Indexes for doctors
CREATE INDEX idx_doctors_user_id ON clinical.doctors(user_id);
CREATE INDEX idx_doctors_employee_id ON clinical.doctors(employee_id);
CREATE INDEX idx_doctors_license ON clinical.doctors(medical_license_number);
CREATE INDEX idx_doctors_specialization ON clinical.doctors(specialization);
CREATE INDEX idx_doctors_department ON clinical.doctors(department_id);
CREATE INDEX idx_doctors_available ON clinical.doctors(is_available);
CREATE INDEX idx_doctors_name ON clinical.doctors(last_name, first_name);

-- ============================================
-- DOCTOR SCHEDULES
-- ============================================

CREATE TABLE clinical.doctor_schedules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    doctor_id UUID REFERENCES clinical.doctors(id) ON DELETE CASCADE NOT NULL,
    
    -- Schedule Details
    day_of_week INTEGER NOT NULL, -- 0=Sunday, 6=Saturday
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    
    -- Break Time
    break_start TIME,
    break_end TIME,
    
    -- Validity
    effective_from DATE DEFAULT CURRENT_DATE NOT NULL,
    effective_until DATE,
    
    -- Status
    is_active BOOLEAN DEFAULT true NOT NULL,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_day_of_week CHECK (day_of_week >= 0 AND day_of_week <= 6),
    CONSTRAINT check_time_order CHECK (end_time > start_time),
    CONSTRAINT check_break_time CHECK (
        (break_start IS NULL AND break_end IS NULL) OR 
        (break_start IS NOT NULL AND break_end IS NOT NULL AND 
         break_end > break_start AND 
         break_start >= start_time AND 
         break_end <= end_time)
    ),
    CONSTRAINT check_effective_dates CHECK (effective_until IS NULL OR effective_until >= effective_from)
);

CREATE INDEX idx_schedules_doctor ON clinical.doctor_schedules(doctor_id);
CREATE INDEX idx_schedules_day ON clinical.doctor_schedules(day_of_week);
CREATE INDEX idx_schedules_active ON clinical.doctor_schedules(is_active);

-- ============================================
-- DOCTOR LEAVES
-- ============================================

CREATE TYPE leave_type_enum AS ENUM ('sick', 'casual', 'emergency', 'vacation', 'conference', 'maternity', 'paternity');
CREATE TYPE leave_status_enum AS ENUM ('pending', 'approved', 'rejected', 'cancelled');

CREATE TABLE clinical.doctor_leaves (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    doctor_id UUID REFERENCES clinical.doctors(id) ON DELETE CASCADE NOT NULL,
    
    -- Leave Details
    leave_type leave_type_enum NOT NULL,
    from_date DATE NOT NULL,
    to_date DATE NOT NULL,
    total_days INTEGER GENERATED ALWAYS AS (to_date - from_date + 1) STORED,
    
    -- Reason
    reason TEXT NOT NULL,
    supporting_documents TEXT[],
    
    -- Status
    status leave_status_enum DEFAULT 'pending' NOT NULL,
    
    -- Approval
    approved_by UUID REFERENCES core.users(id),
    approved_at TIMESTAMP,
    approval_notes TEXT,
    
    -- Cancellation
    cancelled_at TIMESTAMP,
    cancellation_reason TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_leave_dates CHECK (to_date >= from_date),
    CONSTRAINT check_future_leave CHECK (from_date >= CURRENT_DATE - INTERVAL '7 days')
);

CREATE INDEX idx_leaves_doctor ON clinical.doctor_leaves(doctor_id);
CREATE INDEX idx_leaves_dates ON clinical.doctor_leaves(from_date, to_date);
CREATE INDEX idx_leaves_status ON clinical.doctor_leaves(status);

-- ============================================
-- STAFF (Nurses, Technicians, etc.)
-- ============================================

CREATE TYPE staff_role_enum AS ENUM (
    'nurse', 'head_nurse', 'technician', 'receptionist', 
    'pharmacist', 'lab_technician', 'radiologist', 
    'anesthesiologist', 'physiotherapist', 'dietitian', 'other'
);

CREATE TYPE shift_type_enum AS ENUM ('morning', 'evening', 'night', 'rotating', 'on_call');

CREATE TABLE clinical.staff (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE REFERENCES core.users(id) ON DELETE CASCADE NOT NULL,
    
    -- Identification
    employee_id VARCHAR(20) UNIQUE NOT NULL,
    
    -- Personal Information
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE,
    gender gender_enum NOT NULL,
    
    -- Position Information
    role staff_role_enum NOT NULL,
    department_id UUID REFERENCES core.departments(id),
    designation VARCHAR(100),
    
    -- Professional Details
    license_number VARCHAR(50),
    license_expiry DATE,
    qualifications TEXT[],
    certifications TEXT[],
    
    -- Contact Information
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(255) NOT NULL,
    
    -- Work Information
    shift_type shift_type_enum,
    joining_date DATE NOT NULL,
    resignation_date DATE,
    employment_status status_enum DEFAULT 'active',
    
    -- Status
    is_active BOOLEAN DEFAULT true NOT NULL,
    
    -- Media
    photo_url VARCHAR(500),
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_license_valid CHECK (license_expiry IS NULL OR license_expiry > CURRENT_DATE)
);

CREATE INDEX idx_staff_user_id ON clinical.staff(user_id);
CREATE INDEX idx_staff_employee_id ON clinical.staff(employee_id);
CREATE INDEX idx_staff_role ON clinical.staff(role);
CREATE INDEX idx_staff_department ON clinical.staff(department_id);
CREATE INDEX idx_staff_active ON clinical.staff(is_active);

-- ============================================
-- APPLY TRIGGERS
-- ============================================

-- Updated_at triggers
CREATE TRIGGER update_patients_updated_at
    BEFORE UPDATE ON clinical.patients
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_doctors_updated_at
    BEFORE UPDATE ON clinical.doctors
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_staff_updated_at
    BEFORE UPDATE ON clinical.staff
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

-- Audit triggers (CRITICAL for HIPAA)
CREATE TRIGGER audit_patients_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.patients
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_medical_history_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.medical_history
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_allergies_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.patient_allergies
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON TABLE clinical.patients IS 'Patient master data - Contains PHI - HIPAA Protected';
COMMENT ON TABLE clinical.medical_history IS 'Patient medical history - PHI Protected';
COMMENT ON TABLE clinical.patient_allergies IS 'Patient allergies - CRITICAL for safety';
COMMENT ON TABLE clinical.doctors IS 'Doctor profiles and credentials';
COMMENT ON TABLE clinical.doctor_schedules IS 'Doctor availability schedules';

-- ============================================
-- SCHEMA VERSION
-- ============================================

INSERT INTO core.schema_versions (version, description) VALUES
    ('1.1.0', 'Clinical schema: patients, doctors, staff, medical history');

-- ============================================
-- END OF CLINICAL SCHEMA
-- ============================================
