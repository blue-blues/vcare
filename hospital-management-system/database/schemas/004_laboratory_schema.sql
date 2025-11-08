-- ============================================
-- HOSPITAL MANAGEMENT SYSTEM - LABORATORY SCHEMA
-- ============================================
-- ⚠️ CRITICAL: Lab results affect patient treatment decisions
-- Accuracy and validation are paramount

SET search_path TO clinical, core, audit, public;

-- ============================================
-- CUSTOM TYPES
-- ============================================

CREATE TYPE lab_category_enum AS ENUM (
    'hematology',
    'biochemistry',
    'microbiology',
    'pathology',
    'immunology',
    'serology',
    'molecular',
    'toxicology',
    'other'
);

CREATE TYPE sample_type_enum AS ENUM (
    'blood',
    'urine',
    'stool',
    'sputum',
    'csf',
    'tissue',
    'swab',
    'fluid',
    'other'
);

CREATE TYPE lab_order_status_enum AS ENUM (
    'ordered',
    'sample_collected',
    'in_transit',
    'received',
    'in_progress',
    'completed',
    'cancelled',
    'rejected'
);

CREATE TYPE lab_result_status_enum AS ENUM (
    'pending',
    'preliminary',
    'final',
    'corrected',
    'cancelled'
);

CREATE TYPE imaging_modality_enum AS ENUM (
    'xray',
    'ct',
    'mri',
    'ultrasound',
    'pet',
    'mammography',
    'fluoroscopy',
    'nuclear_medicine',
    'other'
);

-- ============================================
-- LAB TESTS CATALOG
-- ============================================

CREATE TABLE clinical.lab_tests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Test Identification
    test_code VARCHAR(20) UNIQUE NOT NULL,
    test_name VARCHAR(255) NOT NULL,
    short_name VARCHAR(100),
    
    -- Classification
    category lab_category_enum NOT NULL,
    sub_category VARCHAR(100),
    department_id UUID REFERENCES core.departments(id),
    
    -- Test Information
    description TEXT,
    clinical_significance TEXT,
    methodology VARCHAR(255),
    
    -- Sample Requirements
    sample_type sample_type_enum NOT NULL,
    sample_volume VARCHAR(50),
    sample_container VARCHAR(100),
    special_handling TEXT,
    
    -- Preparation
    preparation_required BOOLEAN DEFAULT false,
    preparation_instructions TEXT,
    fasting_required BOOLEAN DEFAULT false,
    fasting_hours INTEGER,
    
    -- Timing
    turnaround_time_hours INTEGER NOT NULL,
    stat_available BOOLEAN DEFAULT false,
    stat_turnaround_hours INTEGER,
    
    -- Pricing
    cost DECIMAL(10, 2) NOT NULL,
    insurance_code VARCHAR(50),
    cpt_code VARCHAR(20),
    
    -- Reference Ranges (JSONB for flexibility)
    reference_ranges JSONB NOT NULL,
    /* Example structure:
    {
        "adult_male": {"min": 13.5, "max": 17.5, "unit": "g/dL", "critical_low": 7.0, "critical_high": 20.0},
        "adult_female": {"min": 12.0, "max": 15.5, "unit": "g/dL", "critical_low": 7.0, "critical_high": 20.0},
        "child": {"min": 11.0, "max": 16.0, "unit": "g/dL", "critical_low": 7.0, "critical_high": 18.0},
        "infant": {"min": 10.0, "max": 15.0, "unit": "g/dL", "critical_low": 6.0, "critical_high": 17.0}
    }
    */
    
    -- Status
    is_active BOOLEAN DEFAULT true NOT NULL,
    requires_approval BOOLEAN DEFAULT false,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_cost CHECK (cost >= 0),
    CONSTRAINT check_turnaround CHECK (turnaround_time_hours > 0),
    CONSTRAINT check_stat_turnaround CHECK (stat_turnaround_hours IS NULL OR stat_turnaround_hours > 0)
);

-- Indexes for lab tests
CREATE INDEX idx_lab_tests_code ON clinical.lab_tests(test_code);
CREATE INDEX idx_lab_tests_name ON clinical.lab_tests(test_name);
CREATE INDEX idx_lab_tests_category ON clinical.lab_tests(category);
CREATE INDEX idx_lab_tests_active ON clinical.lab_tests(is_active);

-- Full-text search on test names
CREATE INDEX idx_lab_tests_name_fts ON clinical.lab_tests USING gin(
    to_tsvector('english', test_name || ' ' || COALESCE(description, ''))
);

-- ============================================
-- LAB ORDERS
-- ============================================

CREATE TABLE clinical.lab_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    order_number VARCHAR(20) UNIQUE NOT NULL,
    
    -- References
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    doctor_id UUID REFERENCES clinical.doctors(id) NOT NULL,
    consultation_id UUID REFERENCES clinical.consultations(id),
    
    -- Order Details
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    priority priority_enum DEFAULT 'normal' NOT NULL,
    is_stat BOOLEAN DEFAULT false NOT NULL,
    
    -- Clinical Information
    clinical_notes TEXT,
    diagnosis_code VARCHAR(20),
    provisional_diagnosis TEXT,
    reason_for_test TEXT,
    
    -- Status
    status lab_order_status_enum DEFAULT 'ordered' NOT NULL,
    
    -- Collection Information
    collection_date TIMESTAMP,
    collection_time TIME,
    collected_by UUID REFERENCES clinical.staff(id),
    collection_notes TEXT,
    collection_site VARCHAR(100),
    
    -- Processing
    received_at_lab TIMESTAMP,
    received_by UUID REFERENCES clinical.staff(id),
    processing_started TIMESTAMP,
    processing_completed TIMESTAMP,
    
    -- Reporting
    report_generated BOOLEAN DEFAULT false,
    report_url VARCHAR(500),
    reported_by UUID REFERENCES clinical.staff(id),
    reported_at TIMESTAMP,
    verified_by UUID REFERENCES clinical.doctors(id),
    verified_at TIMESTAMP,
    
    -- Cancellation
    cancelled_at TIMESTAMP,
    cancelled_by UUID REFERENCES core.users(id),
    cancellation_reason TEXT,
    
    -- Billing
    total_cost DECIMAL(10, 2),
    is_billed BOOLEAN DEFAULT false,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_total_cost CHECK (total_cost >= 0)
);

-- Indexes for lab orders
CREATE INDEX idx_lab_orders_number ON clinical.lab_orders(order_number);
CREATE INDEX idx_lab_orders_patient ON clinical.lab_orders(patient_id);
CREATE INDEX idx_lab_orders_doctor ON clinical.lab_orders(doctor_id);
CREATE INDEX idx_lab_orders_status ON clinical.lab_orders(status);
CREATE INDEX idx_lab_orders_date ON clinical.lab_orders(order_date);
CREATE INDEX idx_lab_orders_priority ON clinical.lab_orders(priority);

-- ============================================
-- LAB ORDER ITEMS
-- ============================================

CREATE TABLE clinical.lab_order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- References
    order_id UUID REFERENCES clinical.lab_orders(id) ON DELETE CASCADE NOT NULL,
    test_id UUID REFERENCES clinical.lab_tests(id) NOT NULL,
    
    -- Sample Information
    sample_id VARCHAR(50) UNIQUE NOT NULL, -- Barcode/RFID
    sample_type sample_type_enum NOT NULL,
    sample_collected BOOLEAN DEFAULT false NOT NULL,
    sample_collected_at TIMESTAMP,
    sample_volume VARCHAR(50),
    
    -- Sample Quality
    sample_quality VARCHAR(50), -- adequate, inadequate, hemolyzed, etc.
    sample_rejected BOOLEAN DEFAULT false,
    rejection_reason TEXT,
    
    -- Processing Status
    status lab_result_status_enum DEFAULT 'pending' NOT NULL,
    
    -- Results
    result_value TEXT,
    result_unit VARCHAR(50),
    result_text TEXT, -- For qualitative results
    
    -- Interpretation
    is_abnormal BOOLEAN DEFAULT false,
    abnormality_type VARCHAR(50), -- low, high, critical_low, critical_high
    is_critical BOOLEAN DEFAULT false,
    critical_notified BOOLEAN DEFAULT false,
    critical_notified_at TIMESTAMP,
    
    -- Reference Range (copied from test at time of order)
    reference_range JSONB,
    
    -- Processing Details
    performed_by UUID REFERENCES clinical.staff(id),
    performed_at TIMESTAMP,
    equipment_used VARCHAR(255),
    
    -- Verification
    verified_by UUID REFERENCES clinical.staff(id),
    verified_at TIMESTAMP,
    
    -- Quality Control
    qc_passed BOOLEAN,
    qc_notes TEXT,
    
    -- Comments
    technician_comments TEXT,
    pathologist_comments TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT unique_order_test UNIQUE(order_id, test_id)
);

-- Indexes for lab order items
CREATE INDEX idx_lab_items_order ON clinical.lab_order_items(order_id);
CREATE INDEX idx_lab_items_test ON clinical.lab_order_items(test_id);
CREATE INDEX idx_lab_items_sample ON clinical.lab_order_items(sample_id);
CREATE INDEX idx_lab_items_status ON clinical.lab_order_items(status);
CREATE INDEX idx_lab_items_critical ON clinical.lab_order_items(is_critical);
CREATE INDEX idx_lab_items_abnormal ON clinical.lab_order_items(is_abnormal);

-- ============================================
-- IMAGING ORDERS
-- ============================================

CREATE TABLE clinical.imaging_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    order_number VARCHAR(20) UNIQUE NOT NULL,
    accession_number VARCHAR(50) UNIQUE,
    
    -- References
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    doctor_id UUID REFERENCES clinical.doctors(id) NOT NULL,
    consultation_id UUID REFERENCES clinical.consultations(id),
    
    -- Imaging Details
    modality imaging_modality_enum NOT NULL,
    body_part VARCHAR(100) NOT NULL,
    laterality VARCHAR(20), -- left, right, bilateral
    study_description TEXT NOT NULL,
    
    -- Clinical Information
    clinical_indication TEXT NOT NULL,
    clinical_history TEXT,
    relevant_symptoms TEXT,
    previous_imaging TEXT,
    
    -- Contrast
    contrast_required BOOLEAN DEFAULT false,
    contrast_type VARCHAR(100),
    contrast_volume VARCHAR(50),
    
    -- Scheduling
    scheduled_date DATE,
    scheduled_time TIME,
    priority priority_enum DEFAULT 'normal' NOT NULL,
    is_stat BOOLEAN DEFAULT false,
    
    -- Status
    status lab_order_status_enum DEFAULT 'ordered' NOT NULL,
    
    -- Examination
    performed_date DATE,
    performed_time TIME,
    performed_by UUID REFERENCES clinical.staff(id),
    duration_minutes INTEGER,
    
    -- Technical Details
    technique_used TEXT,
    equipment_used VARCHAR(255),
    protocol_used VARCHAR(255),
    
    -- Results
    findings TEXT,
    impression TEXT,
    recommendations TEXT,
    comparison_studies TEXT,
    
    -- DICOM/PACS Information
    study_instance_uid VARCHAR(255) UNIQUE,
    series_count INTEGER,
    image_count INTEGER,
    pacs_location VARCHAR(500),
    
    -- Reporting
    preliminary_report TEXT,
    final_report TEXT,
    report_status lab_result_status_enum DEFAULT 'pending',
    
    -- Radiologist
    reported_by UUID REFERENCES clinical.doctors(id),
    reported_at TIMESTAMP,
    verified_by UUID REFERENCES clinical.doctors(id),
    verified_at TIMESTAMP,
    
    -- Critical Findings
    has_critical_findings BOOLEAN DEFAULT false,
    critical_findings TEXT,
    critical_notified BOOLEAN DEFAULT false,
    critical_notified_at TIMESTAMP,
    
    -- Billing
    cost DECIMAL(10, 2),
    is_billed BOOLEAN DEFAULT false,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_imaging_cost CHECK (cost >= 0)
);

-- Indexes for imaging orders
CREATE INDEX idx_imaging_orders_number ON clinical.imaging_orders(order_number);
CREATE INDEX idx_imaging_orders_patient ON clinical.imaging_orders(patient_id);
CREATE INDEX idx_imaging_orders_doctor ON clinical.imaging_orders(doctor_id);
CREATE INDEX idx_imaging_orders_modality ON clinical.imaging_orders(modality);
CREATE INDEX idx_imaging_orders_status ON clinical.imaging_orders(status);
CREATE INDEX idx_imaging_orders_date ON clinical.imaging_orders(scheduled_date);
CREATE INDEX idx_imaging_orders_critical ON clinical.imaging_orders(has_critical_findings);

-- Full-text search on findings and impressions
CREATE INDEX idx_imaging_findings_fts ON clinical.imaging_orders USING gin(
    to_tsvector('english', 
        COALESCE(findings, '') || ' ' || 
        COALESCE(impression, '') || ' ' ||
        COALESCE(clinical_indication, '')
    )
);

-- ============================================
-- LAB EQUIPMENT
-- ============================================

CREATE TABLE clinical.lab_equipment (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Equipment Details
    equipment_code VARCHAR(20) UNIQUE NOT NULL,
    equipment_name VARCHAR(255) NOT NULL,
    manufacturer VARCHAR(255),
    model VARCHAR(100),
    serial_number VARCHAR(100) UNIQUE,
    
    -- Classification
    equipment_type VARCHAR(100) NOT NULL,
    department_id UUID REFERENCES core.departments(id),
    
    -- Status
    status VARCHAR(50) DEFAULT 'operational', -- operational, maintenance, out_of_service
    is_active BOOLEAN DEFAULT true NOT NULL,
    
    -- Maintenance
    last_maintenance_date DATE,
    next_maintenance_date DATE,
    maintenance_frequency_days INTEGER,
    
    -- Calibration
    last_calibration_date DATE,
    next_calibration_date DATE,
    calibration_frequency_days INTEGER,
    
    -- Quality Control
    qc_required BOOLEAN DEFAULT true,
    qc_frequency VARCHAR(50), -- daily, weekly, monthly
    last_qc_date DATE,
    
    -- Location
    location VARCHAR(255),
    room_number VARCHAR(50),
    
    -- Purchase Information
    purchase_date DATE,
    purchase_cost DECIMAL(12, 2),
    warranty_expiry DATE,
    
    -- Notes
    notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_purchase_cost CHECK (purchase_cost >= 0)
);

CREATE INDEX idx_equipment_code ON clinical.lab_equipment(equipment_code);
CREATE INDEX idx_equipment_type ON clinical.lab_equipment(equipment_type);
CREATE INDEX idx_equipment_status ON clinical.lab_equipment(status);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Function to generate lab order number
CREATE OR REPLACE FUNCTION clinical.generate_lab_order_number()
RETURNS VARCHAR AS $$
DECLARE
    year_part VARCHAR(4);
    count_part INTEGER;
    new_number VARCHAR(20);
BEGIN
    year_part := TO_CHAR(CURRENT_DATE, 'YYYY');
    
    SELECT COUNT(*) + 1 INTO count_part
    FROM clinical.lab_orders
    WHERE order_number LIKE 'LAB-' || year_part || '-%';
    
    new_number := 'LAB-' || year_part || '-' || LPAD(count_part::TEXT, 6, '0');
    
    RETURN new_number;
END;
$$ LANGUAGE plpgsql;

-- Function to generate imaging order number
CREATE OR REPLACE FUNCTION clinical.generate_imaging_order_number()
RETURNS VARCHAR AS $$
DECLARE
    year_part VARCHAR(4);
    count_part INTEGER;
    new_number VARCHAR(20);
BEGIN
    year_part := TO_CHAR(CURRENT_DATE, 'YYYY');
    
    SELECT COUNT(*) + 1 INTO count_part
    FROM clinical.imaging_orders
    WHERE order_number LIKE 'IMG-' || year_part || '-%';
    
    new_number := 'IMG-' || year_part || '-' || LPAD(count_part::TEXT, 6, '0');
    
    RETURN new_number;
END;
$$ LANGUAGE plpgsql;

-- Function to generate sample barcode
CREATE OR REPLACE FUNCTION clinical.generate_sample_barcode()
RETURNS VARCHAR AS $$
DECLARE
    timestamp_part VARCHAR(14);
    random_part VARCHAR(6);
    barcode VARCHAR(20);
BEGIN
    timestamp_part := TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDDHH24MISS');
    random_part := LPAD(FLOOR(RANDOM() * 999999)::TEXT, 6, '0');
    barcode := 'S' || timestamp_part || random_part;
    
    RETURN barcode;
END;
$$ LANGUAGE plpgsql;

-- Function to check if result is abnormal
CREATE OR REPLACE FUNCTION clinical.check_abnormal_result(
    p_value NUMERIC,
    p_reference_range JSONB,
    p_patient_age INTEGER,
    p_patient_gender VARCHAR
)
RETURNS TABLE(is_abnormal BOOLEAN, abnormality_type VARCHAR, is_critical BOOLEAN) AS $$
DECLARE
    v_range JSONB;
    v_min NUMERIC;
    v_max NUMERIC;
    v_critical_low NUMERIC;
    v_critical_high NUMERIC;
BEGIN
    -- Determine appropriate range based on age and gender
    IF p_patient_age < 1 THEN
        v_range := p_reference_range->'infant';
    ELSIF p_patient_age < 18 THEN
        v_range := p_reference_range->'child';
    ELSIF p_patient_gender = 'male' THEN
        v_range := p_reference_range->'adult_male';
    ELSIF p_patient_gender = 'female' THEN
        v_range := p_reference_range->'adult_female';
    ELSE
        v_range := p_reference_range->'default';
    END IF;
    
    -- Extract values
    v_min := (v_range->>'min')::NUMERIC;
    v_max := (v_range->>'max')::NUMERIC;
    v_critical_low := (v_range->>'critical_low')::NUMERIC;
    v_critical_high := (v_range->>'critical_high')::NUMERIC;
    
    -- Check ranges
    IF p_value < v_critical_low THEN
        RETURN QUERY SELECT true, 'critical_low'::VARCHAR, true;
    ELSIF p_value < v_min THEN
        RETURN QUERY SELECT true, 'low'::VARCHAR, false;
    ELSIF p_value > v_critical_high THEN
        RETURN QUERY SELECT true, 'critical_high'::VARCHAR, true;
    ELSIF p_value > v_max THEN
        RETURN QUERY SELECT true, 'high'::VARCHAR, false;
    ELSE
        RETURN QUERY SELECT false, NULL::VARCHAR, false;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-generate lab order number
CREATE OR REPLACE FUNCTION clinical.set_lab_order_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.order_number IS NULL THEN
        NEW.order_number := clinical.generate_lab_order_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_lab_order_number
    BEFORE INSERT ON clinical.lab_orders
    FOR EACH ROW
    EXECUTE FUNCTION clinical.set_lab_order_number();

-- Auto-generate imaging order number
CREATE OR REPLACE FUNCTION clinical.set_imaging_order_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.order_number IS NULL THEN
        NEW.order_number := clinical.generate_imaging_order_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_imaging_order_number
    BEFORE INSERT ON clinical.imaging_orders
    FOR EACH ROW
    EXECUTE FUNCTION clinical.set_imaging_order_number();

-- Auto-generate sample barcode
CREATE OR REPLACE FUNCTION clinical.set_sample_barcode()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.sample_id IS NULL THEN
        NEW.sample_id := clinical.generate_sample_barcode();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_sample_barcode
    BEFORE INSERT ON clinical.lab_order_items
    FOR EACH ROW
    EXECUTE FUNCTION clinical.set_sample_barcode();

-- Updated_at triggers
CREATE TRIGGER update_lab_tests_updated_at
    BEFORE UPDATE ON clinical.lab_tests
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_lab_orders_updated_at
    BEFORE UPDATE ON clinical.lab_orders
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_lab_items_updated_at
    BEFORE UPDATE ON clinical.lab_order_items
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_imaging_orders_updated_at
    BEFORE UPDATE ON clinical.imaging_orders
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_equipment_updated_at
    BEFORE UPDATE ON clinical.lab_equipment
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

-- Audit triggers (CRITICAL)
CREATE TRIGGER audit_lab_orders_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.lab_orders
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_lab_items_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.lab_order_items
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_imaging_orders_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.imaging_orders
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON TABLE clinical.lab_tests IS 'Laboratory test catalog with reference ranges';
COMMENT ON TABLE clinical.lab_orders IS 'Laboratory test orders - PHI Protected';
COMMENT ON TABLE clinical.lab_order_items IS 'Individual test results - CRITICAL for patient care';
COMMENT ON TABLE clinical.imaging_orders IS 'Radiology and imaging orders - PHI Protected';
COMMENT ON TABLE clinical.lab_equipment IS 'Laboratory equipment tracking and maintenance';
COMMENT ON FUNCTION clinical.check_abnormal_result IS 'Validates lab results against reference ranges - CRITICAL';

-- ============================================
-- SCHEMA VERSION
-- ============================================

INSERT INTO core.schema_versions (version, description) VALUES
    ('1.3.0', 'Laboratory and imaging schema with equipment tracking');

-- ============================================
-- END OF LABORATORY SCHEMA
-- ============================================
