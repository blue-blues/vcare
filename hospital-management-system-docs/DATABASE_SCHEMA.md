# Complete Database Schema Design

## 1. Database Architecture Overview

### 1.1 Multi-Database Strategy
```yaml
PostgreSQL (Primary RDBMS):
  Purpose: Transactional data, relationships, ACID compliance
  Data: Patients, appointments, billing, inventory
  
MongoDB (Document Store):
  Purpose: Unstructured data, flexible schemas
  Data: Medical records, clinical notes, test results
  
Redis (Cache & Session):
  Purpose: High-speed cache, session management
  Data: User sessions, frequently accessed data
  
InfluxDB (Time-Series):
  Purpose: Time-series data, metrics
  Data: Vitals monitoring, system metrics
  
Elasticsearch (Search):
  Purpose: Full-text search, analytics
  Data: Searchable records, logs, analytics
  
Pinecone/Weaviate (Vector DB):
  Purpose: AI embeddings, similarity search
  Data: Medical knowledge, patient similarities
```

## 2. PostgreSQL Schema (Primary Database)

### 2.1 Core Tables

#### Users and Authentication
```sql
-- Users table (base for all user types)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    user_type ENUM('patient', 'doctor', 'nurse', 'admin', 'staff') NOT NULL,
    is_active BOOLEAN DEFAULT true,
    is_verified BOOLEAN DEFAULT false,
    two_factor_enabled BOOLEAN DEFAULT false,
    two_factor_secret VARCHAR(255),
    last_login TIMESTAMP,
    failed_login_attempts INT DEFAULT 0,
    locked_until TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(id),
    updated_by UUID REFERENCES users(id),
    CONSTRAINT check_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Roles and permissions
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    is_system BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource VARCHAR(100) NOT NULL,
    action VARCHAR(50) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(resource, action)
);

CREATE TABLE role_permissions (
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES permissions(id) ON DELETE CASCADE,
    granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    granted_by UUID REFERENCES users(id),
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    assigned_by UUID REFERENCES users(id),
    expires_at TIMESTAMP,
    PRIMARY KEY (user_id, role_id)
);

-- Audit log for all database changes
CREATE TABLE audit_log (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id UUID NOT NULL,
    action VARCHAR(20) NOT NULL, -- INSERT, UPDATE, DELETE
    user_id UUID REFERENCES users(id),
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for audit log
CREATE INDEX idx_audit_log_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_user ON audit_log(user_id);
CREATE INDEX idx_audit_log_created ON audit_log(created_at);
```

#### Patient Management
```sql
-- Patients table
CREATE TABLE patients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    patient_number VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender ENUM('male', 'female', 'other') NOT NULL,
    blood_group ENUM('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'),
    marital_status ENUM('single', 'married', 'divorced', 'widowed'),
    occupation VARCHAR(100),
    nationality VARCHAR(100),
    religion VARCHAR(50),
    
    -- Contact Information
    phone_primary VARCHAR(20) NOT NULL,
    phone_secondary VARCHAR(20),
    email VARCHAR(255),
    
    -- Address
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    city VARCHAR(100),
    state VARCHAR(100),
    country VARCHAR(100),
    postal_code VARCHAR(20),
    
    -- Emergency Contact
    emergency_contact_name VARCHAR(200),
    emergency_contact_relationship VARCHAR(50),
    emergency_contact_phone VARCHAR(20),
    
    -- Medical Information
    allergies TEXT[],
    chronic_conditions TEXT[],
    current_medications TEXT[],
    
    -- Biometric Data
    photo_url VARCHAR(500),
    fingerprint_data BYTEA,
    iris_scan_data BYTEA,
    
    -- Metadata
    registration_date DATE DEFAULT CURRENT_DATE,
    last_visit_date DATE,
    visit_count INT DEFAULT 0,
    is_vip BOOLEAN DEFAULT false,
    is_blacklisted BOOLEAN DEFAULT false,
    blacklist_reason TEXT,
    notes TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(id),
    updated_by UUID REFERENCES users(id),
    
    CONSTRAINT check_age CHECK (date_of_birth <= CURRENT_DATE),
    CONSTRAINT check_phone CHECK (phone_primary ~ '^[0-9+\-() ]+$')
);

-- Patient medical history
CREATE TABLE medical_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    condition_name VARCHAR(255) NOT NULL,
    icd_code VARCHAR(20),
    diagnosed_date DATE,
    resolved_date DATE,
    is_chronic BOOLEAN DEFAULT false,
    severity ENUM('mild', 'moderate', 'severe', 'critical'),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(id)
);

-- Patient allergies (detailed)
CREATE TABLE patient_allergies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    allergen_type ENUM('drug', 'food', 'environmental', 'other') NOT NULL,
    allergen_name VARCHAR(255) NOT NULL,
    reaction_type VARCHAR(255),
    severity ENUM('mild', 'moderate', 'severe', 'life-threatening'),
    onset_date DATE,
    notes TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    verified_by UUID REFERENCES users(id),
    UNIQUE(patient_id, allergen_name)
);

-- Family medical history
CREATE TABLE family_medical_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    relationship ENUM('father', 'mother', 'sibling', 'grandparent', 'other') NOT NULL,
    condition_name VARCHAR(255) NOT NULL,
    age_at_diagnosis INT,
    is_deceased BOOLEAN DEFAULT false,
    cause_of_death VARCHAR(255),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insurance information
CREATE TABLE patient_insurance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    insurance_provider VARCHAR(255) NOT NULL,
    policy_number VARCHAR(100) UNIQUE NOT NULL,
    group_number VARCHAR(100),
    policy_holder_name VARCHAR(255),
    policy_holder_relationship ENUM('self', 'spouse', 'parent', 'other'),
    valid_from DATE NOT NULL,
    valid_until DATE NOT NULL,
    coverage_type ENUM('basic', 'premium', 'comprehensive'),
    coverage_amount DECIMAL(12, 2),
    copay_percentage DECIMAL(5, 2),
    deductible DECIMAL(10, 2),
    is_primary BOOLEAN DEFAULT true,
    is_active BOOLEAN DEFAULT true,
    verification_status ENUM('pending', 'verified', 'rejected') DEFAULT 'pending',
    verification_date TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_validity CHECK (valid_until > valid_from)
);
```

#### Doctor and Staff Management
```sql
-- Doctors table
CREATE TABLE doctors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    employee_id VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    
    -- Professional Information
    medical_license_number VARCHAR(50) UNIQUE NOT NULL,
    medical_license_expiry DATE NOT NULL,
    specialization VARCHAR(100) NOT NULL,
    sub_specialization VARCHAR(100),
    qualification TEXT[],
    years_of_experience INT,
    
    -- Department and Position
    department_id UUID REFERENCES departments(id),
    designation VARCHAR(100),
    is_consultant BOOLEAN DEFAULT false,
    is_surgeon BOOLEAN DEFAULT false,
    
    -- Contact Information
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(255) NOT NULL,
    office_room VARCHAR(50),
    
    -- Availability
    consultation_fee DECIMAL(10, 2),
    consultation_duration_minutes INT DEFAULT 30,
    is_available BOOLEAN DEFAULT true,
    max_daily_appointments INT DEFAULT 20,
    
    -- Ratings and Performance
    rating DECIMAL(3, 2) DEFAULT 0.00,
    total_reviews INT DEFAULT 0,
    patients_treated INT DEFAULT 0,
    
    -- Metadata
    joining_date DATE NOT NULL,
    resignation_date DATE,
    photo_url VARCHAR(500),
    digital_signature BYTEA,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT check_rating CHECK (rating >= 0 AND rating <= 5),
    CONSTRAINT check_license_expiry CHECK (medical_license_expiry > CURRENT_DATE)
);

-- Doctor schedules
CREATE TABLE doctor_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID REFERENCES doctors(id) ON DELETE CASCADE,
    day_of_week INT NOT NULL, -- 0=Sunday, 6=Saturday
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    break_start TIME,
    break_end TIME,
    is_active BOOLEAN DEFAULT true,
    effective_from DATE DEFAULT CURRENT_DATE,
    effective_until DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_day CHECK (day_of_week >= 0 AND day_of_week <= 6),
    CONSTRAINT check_time CHECK (end_time > start_time),
    CONSTRAINT check_break CHECK (
        (break_start IS NULL AND break_end IS NULL) OR 
        (break_start IS NOT NULL AND break_end IS NOT NULL AND break_end > break_start)
    )
);

-- Doctor leave management
CREATE TABLE doctor_leaves (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id UUID REFERENCES doctors(id) ON DELETE CASCADE,
    leave_type ENUM('sick', 'casual', 'emergency', 'vacation', 'conference') NOT NULL,
    from_date DATE NOT NULL,
    to_date DATE NOT NULL,
    reason TEXT,
    status ENUM('pending', 'approved', 'rejected', 'cancelled') DEFAULT 'pending',
    approved_by UUID REFERENCES users(id),
    approved_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_dates CHECK (to_date >= from_date)
);

-- Nurses and other staff
CREATE TABLE staff (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    employee_id VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    
    -- Position Information
    role ENUM('nurse', 'technician', 'receptionist', 'pharmacist', 'lab_technician', 'admin', 'other') NOT NULL,
    department_id UUID REFERENCES departments(id),
    designation VARCHAR(100),
    
    -- Contact Information
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(255) NOT NULL,
    
    -- Work Information
    shift_type ENUM('morning', 'evening', 'night', 'rotating'),
    is_active BOOLEAN DEFAULT true,
    
    -- Metadata
    joining_date DATE NOT NULL,
    resignation_date DATE,
    photo_url VARCHAR(500),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Departments
CREATE TABLE departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) UNIQUE NOT NULL,
    code VARCHAR(20) UNIQUE NOT NULL,
    description TEXT,
    head_doctor_id UUID REFERENCES doctors(id),
    floor_number INT,
    extension_number VARCHAR(20),
    is_emergency BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### Appointments and Consultations
```sql
-- Appointments
CREATE TABLE appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_number VARCHAR(20) UNIQUE NOT NULL,
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    doctor_id UUID REFERENCES doctors(id),
    department_id UUID REFERENCES departments(id),
    
    -- Scheduling Information
    appointment_date DATE NOT NULL,
    appointment_time TIME NOT NULL,
    duration_minutes INT DEFAULT 30,
    appointment_type ENUM('consultation', 'follow-up', 'procedure', 'emergency', 'telemedicine') NOT NULL,
    
    -- Status Tracking
    status ENUM('scheduled', 'confirmed', 'checked-in', 'in-progress', 'completed', 'cancelled', 'no-show') DEFAULT 'scheduled',
    check_in_time TIMESTAMP,
    consultation_start_time TIMESTAMP,
    consultation_end_time TIMESTAMP,
    
    -- Additional Information
    reason_for_visit TEXT,
    symptoms TEXT[],
    priority ENUM('normal', 'urgent', 'emergency') DEFAULT 'normal',
    is_first_visit BOOLEAN DEFAULT false,
    referred_by VARCHAR(255),
    
    -- Cancellation/Rescheduling
    cancelled_at TIMESTAMP,
    cancelled_by UUID REFERENCES users(id),
    cancellation_reason TEXT,
    rescheduled_from UUID REFERENCES appointments(id),
    
    -- Notifications
    reminder_sent BOOLEAN DEFAULT false,
    reminder_sent_at TIMESTAMP,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(id),
    
    CONSTRAINT check_appointment_time CHECK (appointment_date >= CURRENT_DATE),
    UNIQUE(doctor_id, appointment_date, appointment_time)
);

-- Consultation records
CREATE TABLE consultations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id UUID REFERENCES appointments(id),
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    doctor_id UUID REFERENCES doctors(id),
    
    -- Vital Signs
    blood_pressure_systolic INT,
    blood_pressure_diastolic INT,
    pulse_rate INT,
    temperature DECIMAL(4, 1),
    respiratory_rate INT,
    oxygen_saturation DECIMAL(5, 2),
    weight DECIMAL(5, 2),
    height DECIMAL(5, 2),
    bmi DECIMAL(4, 2),
    
    -- Clinical Information
    chief_complaint TEXT,
    history_of_present_illness TEXT,
    physical_examination TEXT,
    
    -- Diagnosis
    provisional_diagnosis TEXT,
    final_diagnosis TEXT,
    icd_codes TEXT[],
    
    -- Treatment Plan
    treatment_plan TEXT,
    follow_up_required BOOLEAN DEFAULT false,
    follow_up_date DATE,
    
    -- Clinical Notes
    clinical_notes TEXT,
    private_notes TEXT, -- Only visible to doctor
    
    -- Attachments and References
    attachment_urls TEXT[],
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Prescriptions
CREATE TABLE prescriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prescription_number VARCHAR(20) UNIQUE NOT NULL,
    consultation_id UUID REFERENCES consultations(id),
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    doctor_id UUID REFERENCES doctors(id),
    
    -- Prescription Status
    status ENUM('draft', 'active', 'dispensed', 'completed', 'cancelled') DEFAULT 'draft',
    
    -- Validity
    prescribed_date DATE DEFAULT CURRENT_DATE,
    valid_until DATE,
    
    -- Pharmacy Information
    dispensed_by UUID REFERENCES staff(id),
    dispensed_at TIMESTAMP,
    pharmacy_notes TEXT,
    
    -- Digital Signature
    is_signed BOOLEAN DEFAULT false,
    signed_at TIMESTAMP,
    signature_hash VARCHAR(255),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Prescription items (individual medicines)
CREATE TABLE prescription_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prescription_id UUID REFERENCES prescriptions(id) ON DELETE CASCADE,
    medicine_id UUID REFERENCES medicines(id),
    
    -- Dosage Information
    dosage VARCHAR(100) NOT NULL,
    dosage_unit ENUM('mg', 'ml', 'tablet', 'capsule', 'drops', 'puff', 'unit'),
    frequency VARCHAR(100) NOT NULL, -- "1-0-1", "twice daily", etc.
    duration_days INT NOT NULL,
    
    -- Instructions
    route ENUM('oral', 'injection', 'topical', 'inhalation', 'rectal', 'nasal', 'ophthalmic', 'otic'),
    food_relation ENUM('before_food', 'after_food', 'with_food', 'empty_stomach'),
    special_instructions TEXT,
    
    -- Dispensing Information
    quantity_prescribed INT NOT NULL,
    quantity_dispensed INT DEFAULT 0,
    refills_allowed INT DEFAULT 0,
    refills_remaining INT DEFAULT 0,
    
    -- Substitution
    allow_substitution BOOLEAN DEFAULT true,
    substituted_with UUID REFERENCES medicines(id),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### Laboratory and Diagnostics
```sql
-- Lab tests catalog
CREATE TABLE lab_tests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    test_code VARCHAR(20) UNIQUE NOT NULL,
    test_name VARCHAR(255) NOT NULL,
    category ENUM('hematology', 'biochemistry', 'microbiology', 'pathology', 'radiology', 'cardiology', 'other') NOT NULL,
    sub_category VARCHAR(100),
    
    -- Test Information
    description TEXT,
    preparation_required TEXT,
    fasting_required BOOLEAN DEFAULT false,
    sample_type ENUM('blood', 'urine', 'stool', 'sputum', 'tissue', 'other'),
    sample_volume VARCHAR(50),
    
    -- Timing and Cost
    turnaround_time_hours INT,
    cost DECIMAL(10, 2),
    
    -- Reference Ranges (stored as JSONB for flexibility)
    reference_ranges JSONB,
    /* Example:
    {
        "male": {"min": 13.5, "max": 17.5, "unit": "g/dL"},
        "female": {"min": 12.0, "max": 15.5, "unit": "g/dL"},
        "child": {"min": 11.0, "max": 16.0, "unit": "g/dL"}
    }
    */
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Lab orders
CREATE TABLE lab_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number VARCHAR(20) UNIQUE NOT NULL,
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    doctor_id UUID REFERENCES doctors(id),
    consultation_id UUID REFERENCES consultations(id),
    
    -- Order Information
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    priority ENUM('routine', 'urgent', 'stat') DEFAULT 'routine',
    clinical_notes TEXT,
    diagnosis_code VARCHAR(20),
    
    -- Status Tracking
    status ENUM('ordered', 'sample_collected', 'in_progress', 'completed', 'cancelled') DEFAULT 'ordered',
    
    -- Collection Information
    collection_date TIMESTAMP,
    collected_by UUID REFERENCES staff(id),
    collection_notes TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Lab order items
CREATE TABLE lab_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES lab_orders(id) ON DELETE CASCADE,
    test_id UUID REFERENCES lab_tests(id),
    
    -- Sample Information
    sample_id VARCHAR(50) UNIQUE, -- Barcode/RFID
    sample_collected BOOLEAN DEFAULT false,
    sample_collected_at TIMESTAMP,
    
    -- Processing
    status ENUM('pending', 'collected', 'processing', 'completed', 'rejected') DEFAULT 'pending',
    rejection_reason TEXT,
    
    -- Results
    result_value TEXT,
    result_unit VARCHAR(50),
    is_abnormal BOOLEAN DEFAULT false,
    abnormality_type ENUM('low', 'high', 'critical_low', 'critical_high'),
    
    -- Verification
    performed_by UUID REFERENCES staff(id),
    performed_at TIMESTAMP,
    verified_by UUID REFERENCES staff(id),
    verified_at TIMESTAMP,
    
    comments TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Imaging orders
CREATE TABLE imaging_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number VARCHAR(20) UNIQUE NOT NULL,
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    doctor_id UUID REFERENCES doctors(id),
    consultation_id UUID REFERENCES consultations(id),
    
    -- Imaging Information
    modality ENUM('xray', 'ct', 'mri', 'ultrasound', 'pet', 'mammography', 'other') NOT NULL,
    body_part VARCHAR(100),
    study_description TEXT,
    clinical_indication TEXT,
    
    -- Scheduling
    scheduled_date DATE,
    scheduled_time TIME,
    
    -- Status
    status ENUM('ordered', 'scheduled', 'in_progress', 'completed', 'cancelled') DEFAULT 'ordered',
    
    -- Results
    findings TEXT,
    impression TEXT,
    recommendations TEXT,
    
    -- DICOM/PACS Information
    study_instance_uid VARCHAR(255) UNIQUE,
    accession_number VARCHAR(50),
    image_count INT,
    
    -- Reporting
    reported_by UUID REFERENCES doctors(id),
    reported_at TIMESTAMP,
    report_verified_by UUID REFERENCES doctors(id),
    report_verified_at TIMESTAMP,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### Pharmacy and Inventory
```sql
-- Medicines catalog
CREATE TABLE medicines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    medicine_code VARCHAR(20) UNIQUE NOT NULL,
    brand_name VARCHAR(255) NOT NULL,
    generic_name VARCHAR(255) NOT NULL,
    manufacturer VARCHAR(255),
    
    -- Classification
    category VARCHAR(100),
    drug_class VARCHAR(100),
    controlled_substance BOOLEAN DEFAULT false,
    schedule_type VARCHAR(10), -- Schedule II, III, IV, V
    
    -- Formulation
    form ENUM('tablet', 'capsule', 'syrup', 'injection', 'cream', 'ointment', 'drops', 'inhaler', 'patch', 'other'),
    strength VARCHAR(100),
    unit_of_measure VARCHAR(50),
    
    -- Storage
    storage_conditions TEXT,
    
    -- Pricing
    unit_price DECIMAL(10, 2),
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Pharmacy inventory
CREATE TABLE pharmacy_inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    medicine_id UUID REFERENCES medicines(id),
    
    -- Stock Information
    batch_number VARCHAR(50) NOT NULL,
    quantity_in_stock INT NOT NULL,
    unit_of_measure VARCHAR(50),
    
    -- Dates
    manufacture_date DATE,
    expiry_date DATE NOT NULL,
    received_date DATE DEFAULT CURRENT_DATE,
    
    -- Thresholds
    reorder_level INT,
    max_stock_level INT,
    
    -- Supplier Information
    supplier_id UUID REFERENCES suppliers(id),
    purchase_price DECIMAL(10, 2),
    
    -- Location
    storage_location VARCHAR(100),
    
    is_quarantined BOOLEAN DEFAULT false,
    quarantine_reason TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT check_expiry CHECK (expiry_date > CURRENT_DATE),
    CONSTRAINT check_stock CHECK (quantity_in_stock >= 0),
    UNIQUE(medicine_id, batch_number)
);

-- Pharmacy transactions
CREATE TABLE pharmacy_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_type ENUM('purchase', 'sale', 'return', 'adjustment', 'expired', 'damaged') NOT NULL,
    medicine_id UUID REFERENCES medicines(id),
    batch_number VARCHAR(50),
    
    -- Transaction Details
    quantity INT NOT NULL,
    unit_price DECIMAL(10, 2),
    total_amount DECIMAL(12, 2),
    
    -- Reference
    reference_type ENUM('prescription', 'purchase_order', 'adjustment', 'other'),
    reference_id UUID,
    
    -- Patient/Supplier
    patient_id UUID REFERENCES patients(id),
    supplier_id UUID REFERENCES suppliers(id),
    
    -- Metadata
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    performed_by UUID REFERENCES users(id),
    notes TEXT
);

-- Suppliers
CREATE TABLE suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_code VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    contact_person VARCHAR(255),
    phone VARCHAR(20),
    email VARCHAR(255),
    address TEXT,
    
    -- Business Information
    tax_id VARCHAR(50),
    license_number VARCHAR(50),
    
    -- Terms
    payment_terms VARCHAR(100),
    delivery_terms VARCHAR(100),
    
    -- Performance
    rating DECIMAL(3, 2),
    total_orders INT DEFAULT 0,
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### Billing and Payments
```sql
-- Bills
CREATE TABLE bills (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bill_number VARCHAR(20) UNIQUE NOT NULL,
    patient_id UUID REFERENCES patients(id) ON DELETE CASCADE,
    
    -- Bill Type
    bill_type ENUM('opd', 'ipd', 'emergency', 'pharmacy', 'lab', 'procedure') NOT NULL,
    
    -- Amounts
    subtotal DECIMAL(12, 2) NOT NULL,
    tax_amount DECIMAL(10, 2) DEFAULT 0,
    discount_amount DECIMAL(10, 2) DEFAULT 0,
    total_amount DECIMAL(12, 2) NOT NULL,
    paid_amount DECIMAL(12, 2) DEFAULT 0,
    balance_amount DECIMAL(12, 2) GENERATED ALWAYS AS (total_amount - paid_amount) STORED,
    
    -- Status
    status ENUM('draft', 'pending', 'partial', 'paid', 'cancelled', 'refunded') DEFAULT 'draft',
    
    -- Insurance
    insurance_claim_id UUID REFERENCES insurance_claims(id),
    insurance_covered_amount DECIMAL(12, 2) DEFAULT 0,
    patient_copay_amount DECIMAL(12, 2) DEFAULT 0,
    
    -- Dates
    bill_date DATE DEFAULT CURRENT_DATE,
    due_date DATE,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(id)
);

-- Bill items
CREATE TABLE bill_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bill_id UUID REFERENCES bills(id) ON DELETE CASCADE,
    
    -- Item Information
    item_type ENUM('consultation', 'procedure', 'medicine', 'lab_test', 'room_charge', 'other') NOT NULL,
    item_code VARCHAR(50),
    item_name VARCHAR(255) NOT NULL,
    
    -- Reference to actual item
    reference_type VARCHAR(50),
    reference_id UUID,
    
    -- Pricing
    quantity INT DEFAULT 1,
    unit_price DECIMAL(10, 2) NOT NULL,
    discount_percentage DECIMAL(5, 2) DEFAULT 0,
    tax_percentage DECIMAL(5, 2) DEFAULT 0,
    total_amount DECIMAL(12, 2) NOT NULL,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Payments
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_number VARCHAR(20) UNIQUE NOT NULL,
    bill_id UUID REFERENCES bills(id),
    patient_id UUID REFERENCES patients(id),
    
    -- Payment Information
    amount DECIMAL(12, 2) NOT NULL,
    payment_method ENUM('cash', 'card', 'check', 'bank_transfer', 'insurance', 'online') NOT NULL,
    
    -- Payment Details
    transaction_id VARCHAR(100),
    card_last_four VARCHAR(4),
    check_number VARCHAR(50),
    bank_name VARCHAR(100),
    
    -- Status
    status ENUM('pending', 'completed', 'failed', 'refunded') DEFAULT 'pending',
    
    -- Metadata
    payment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    received_by UUID REFERENCES users(id),
    notes TEXT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insurance claims
CREATE TABLE insurance_claims (
    id UUID PRIMARY KEY DEFAULT gen_random_uui
