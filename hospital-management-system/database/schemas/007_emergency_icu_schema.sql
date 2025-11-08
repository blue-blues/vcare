-- ============================================
-- HOSPITAL MANAGEMENT SYSTEM - EMERGENCY & ICU SCHEMA
-- ============================================
-- ⚠️ CRITICAL: This handles life-threatening situations
-- Real-time accuracy and immediate response required
-- Every second counts - system must be highly available

SET search_path TO clinical, core, audit, public;

-- ============================================
-- CUSTOM TYPES
-- ============================================

CREATE TYPE triage_level_enum AS ENUM (
    'level_1_resuscitation',  -- Immediate, life-threatening
    'level_2_emergent',        -- 10 minutes
    'level_3_urgent',          -- 30 minutes
    'level_4_less_urgent',     -- 60 minutes
    'level_5_non_urgent'       -- 120 minutes
);

CREATE TYPE emergency_status_enum AS ENUM (
    'arrived',
    'triaged',
    'in_treatment',
    'stabilized',
    'admitted',
    'discharged',
    'transferred',
    'deceased'
);

CREATE TYPE icu_admission_type_enum AS ENUM (
    'medical',
    'surgical',
    'cardiac',
    'neurological',
    'trauma',
    'respiratory',
    'post_operative',
    'other'
);

CREATE TYPE bed_status_enum AS ENUM (
    'available',
    'occupied',
    'reserved',
    'cleaning',
    'maintenance',
    'out_of_service'
);

CREATE TYPE ventilator_mode_enum AS ENUM (
    'assist_control',
    'simv',
    'pressure_support',
    'cpap',
    'bipap',
    'prvc',
    'other'
);

-- ============================================
-- EMERGENCY CASES
-- ============================================

CREATE TABLE clinical.emergency_cases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    case_number VARCHAR(20) UNIQUE NOT NULL,
    
    -- Patient
    patient_id UUID REFERENCES clinical.patients(id),
    
    -- For unidentified patients
    is_unidentified BOOLEAN DEFAULT false NOT NULL,
    temporary_id VARCHAR(50),
    estimated_age INTEGER,
    estimated_gender gender_enum,
    
    -- Arrival Information
    arrival_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    arrival_mode VARCHAR(50) NOT NULL, -- ambulance, walk-in, police, helicopter
    ambulance_number VARCHAR(50),
    
    -- Triage
    triage_level triage_level_enum NOT NULL,
    triage_time TIMESTAMP NOT NULL,
    triaged_by UUID REFERENCES clinical.staff(id) NOT NULL,
    triage_notes TEXT NOT NULL,
    
    -- Chief Complaint
    chief_complaint TEXT NOT NULL,
    presenting_symptoms TEXT[] NOT NULL,
    
    -- Vital Signs at Arrival
    blood_pressure_systolic INTEGER,
    blood_pressure_diastolic INTEGER,
    pulse_rate INTEGER,
    temperature DECIMAL(4, 1),
    respiratory_rate INTEGER,
    oxygen_saturation DECIMAL(5, 2),
    glasgow_coma_scale INTEGER, -- 3-15
    pain_scale INTEGER, -- 0-10
    
    -- Status
    status emergency_status_enum DEFAULT 'arrived' NOT NULL,
    
    -- Treatment
    attending_doctor_id UUID REFERENCES clinical.doctors(id),
    treatment_start_time TIMESTAMP,
    treatment_end_time TIMESTAMP,
    
    -- Outcome
    disposition VARCHAR(50), -- admitted, discharged, transferred, deceased, left_ama
    disposition_time TIMESTAMP,
    disposition_notes TEXT,
    
    -- Admission (if admitted)
    admitted_to_ward VARCHAR(100),
    admitted_to_icu BOOLEAN DEFAULT false,
    admission_id UUID,
    
    -- Transfer (if transferred)
    transferred_to VARCHAR(255),
    transfer_reason TEXT,
    transfer_time TIMESTAMP,
    
    -- Critical Alerts
    is_critical BOOLEAN DEFAULT false NOT NULL,
    critical_alerts TEXT[],
    
    -- Accompanying Person
    accompanying_person_name VARCHAR(255),
    accompanying_person_phone VARCHAR(20),
    accompanying_person_relationship VARCHAR(50),
    
    -- Police Case
    is_police_case BOOLEAN DEFAULT false,
    police_station VARCHAR(255),
    fir_number VARCHAR(50),
    police_officer_name VARCHAR(255),
    police_officer_badge VARCHAR(50),
    
    -- Medico-Legal Case
    is_mlc BOOLEAN DEFAULT false,
    mlc_number VARCHAR(50),
    mlc_type VARCHAR(100),
    
    -- Notes
    clinical_notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_gcs CHECK (glasgow_coma_scale IS NULL OR (glasgow_coma_scale >= 3 AND glasgow_coma_scale <= 15)),
    CONSTRAINT check_pain_scale CHECK (pain_scale IS NULL OR (pain_scale >= 0 AND pain_scale <= 10)),
    CONSTRAINT check_estimated_age CHECK (estimated_age IS NULL OR (estimated_age >= 0 AND estimated_age <= 150))
);

-- Indexes for emergency cases
CREATE INDEX idx_emergency_case_number ON clinical.emergency_cases(case_number);
CREATE INDEX idx_emergency_patient ON clinical.emergency_cases(patient_id);
CREATE INDEX idx_emergency_triage ON clinical.emergency_cases(triage_level);
CREATE INDEX idx_emergency_status ON clinical.emergency_cases(status);
CREATE INDEX idx_emergency_arrival ON clinical.emergency_cases(arrival_date);
CREATE INDEX idx_emergency_critical ON clinical.emergency_cases(is_critical);
CREATE INDEX idx_emergency_unidentified ON clinical.emergency_cases(is_unidentified) WHERE is_unidentified = true;

-- ============================================
-- ICU BEDS
-- ============================================

CREATE TABLE clinical.icu_beds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Bed Identification
    bed_number VARCHAR(20) UNIQUE NOT NULL,
    bed_code VARCHAR(10) UNIQUE NOT NULL,
    
    -- Location
    icu_unit VARCHAR(100) NOT NULL, -- ICU, NICU, PICU, CCU, etc.
    floor_number INTEGER,
    room_number VARCHAR(20),
    
    -- Bed Type
    bed_type VARCHAR(50) NOT NULL, -- general, isolation, negative_pressure
    
    -- Equipment
    has_ventilator BOOLEAN DEFAULT false NOT NULL,
    has_monitor BOOLEAN DEFAULT true NOT NULL,
    has_infusion_pump BOOLEAN DEFAULT false NOT NULL,
    has_dialysis BOOLEAN DEFAULT false NOT NULL,
    
    -- Status
    status bed_status_enum DEFAULT 'available' NOT NULL,
    
    -- Current Occupancy
    current_patient_id UUID REFERENCES clinical.patients(id),
    occupied_since TIMESTAMP,
    
    -- Maintenance
    last_cleaned TIMESTAMP,
    last_maintenance TIMESTAMP,
    next_maintenance_due DATE,
    
    -- Notes
    notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    is_active BOOLEAN DEFAULT true NOT NULL,
    
    CONSTRAINT check_floor CHECK (floor_number > 0)
);

-- Indexes for ICU beds
CREATE INDEX idx_icu_beds_number ON clinical.icu_beds(bed_number);
CREATE INDEX idx_icu_beds_unit ON clinical.icu_beds(icu_unit);
CREATE INDEX idx_icu_beds_status ON clinical.icu_beds(status);
CREATE INDEX idx_icu_beds_patient ON clinical.icu_beds(current_patient_id);
CREATE INDEX idx_icu_beds_available ON clinical.icu_beds(status, icu_unit) WHERE status = 'available';

-- ============================================
-- ICU ADMISSIONS
-- ============================================

CREATE TABLE clinical.icu_admissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    admission_number VARCHAR(20) UNIQUE NOT NULL,
    
    -- Patient and Bed
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    bed_id UUID REFERENCES clinical.icu_beds(id) NOT NULL,
    
    -- Admission Details
    admission_type icu_admission_type_enum NOT NULL,
    admission_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    admission_source VARCHAR(50) NOT NULL, -- emergency, operation_theater, ward, transfer
    
    -- Clinical Information
    primary_diagnosis TEXT NOT NULL,
    secondary_diagnoses TEXT[],
    icd_codes TEXT[],
    
    -- Severity Scores
    apache_score INTEGER, -- APACHE II score (0-71)
    sofa_score INTEGER, -- Sequential Organ Failure Assessment (0-24)
    glasgow_coma_scale INTEGER, -- 3-15
    
    -- Attending Team
    primary_doctor_id UUID REFERENCES clinical.doctors(id) NOT NULL,
    consulting_doctors UUID[],
    primary_nurse_id UUID REFERENCES clinical.staff(id),
    
    -- Ventilation
    is_ventilated BOOLEAN DEFAULT false NOT NULL,
    ventilation_start TIMESTAMP,
    ventilation_end TIMESTAMP,
    ventilator_mode ventilator_mode_enum,
    
    -- Monitoring
    requires_continuous_monitoring BOOLEAN DEFAULT true NOT NULL,
    isolation_required BOOLEAN DEFAULT false,
    isolation_type VARCHAR(50),
    
    -- Status
    status VARCHAR(50) DEFAULT 'active' NOT NULL, -- active, discharged, transferred, deceased
    
    -- Discharge/Transfer
    discharge_date TIMESTAMP,
    discharge_destination VARCHAR(100), -- ward, home, transferred, deceased
    discharge_summary TEXT,
    discharged_by UUID REFERENCES clinical.doctors(id),
    
    -- Length of Stay
    total_days INTEGER GENERATED ALWAYS AS (
        EXTRACT(DAY FROM COALESCE(discharge_date, CURRENT_TIMESTAMP) - admission_date)
    ) STORED,
    
    -- Notes
    admission_notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_apache_score CHECK (apache_score IS NULL OR (apache_score >= 0 AND apache_score <= 71)),
    CONSTRAINT check_sofa_score CHECK (sofa_score IS NULL OR (sofa_score >= 0 AND sofa_score <= 24)),
    CONSTRAINT check_gcs_icu CHECK (glasgow_coma_scale IS NULL OR (glasgow_coma_scale >= 3 AND glasgow_coma_scale <= 15)),
    CONSTRAINT check_discharge_after_admission CHECK (discharge_date IS NULL OR discharge_date >= admission_date)
);

-- Indexes for ICU admissions
CREATE INDEX idx_icu_admissions_number ON clinical.icu_admissions(admission_number);
CREATE INDEX idx_icu_admissions_patient ON clinical.icu_admissions(patient_id);
CREATE INDEX idx_icu_admissions_bed ON clinical.icu_admissions(bed_id);
CREATE INDEX idx_icu_admissions_status ON clinical.icu_admissions(status);
CREATE INDEX idx_icu_admissions_date ON clinical.icu_admissions(admission_date);
CREATE INDEX idx_icu_admissions_doctor ON clinical.icu_admissions(primary_doctor_id);

-- ============================================
-- ICU VITAL SIGNS MONITORING
-- ============================================

CREATE TABLE clinical.icu_vitals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- References
    admission_id UUID REFERENCES clinical.icu_admissions(id) ON DELETE CASCADE NOT NULL,
    patient_id UUID REFERENCES clinical.patients(id) NOT NULL,
    
    -- Timestamp
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    recorded_by UUID REFERENCES clinical.staff(id) NOT NULL,
    
    -- Vital Signs
    blood_pressure_systolic INTEGER,
    blood_pressure_diastolic INTEGER,
    mean_arterial_pressure INTEGER,
    heart_rate INTEGER,
    temperature DECIMAL(4, 1),
    respiratory_rate INTEGER,
    oxygen_saturation DECIMAL(5, 2),
    
    -- Respiratory
    fio2 INTEGER, -- Fraction of inspired oxygen (21-100%)
    peep INTEGER, -- Positive end-expiratory pressure
    tidal_volume INTEGER,
    minute_ventilation DECIMAL(5, 2),
    
    -- Neurological
    glasgow_coma_scale INTEGER,
    pupil_size_left DECIMAL(3, 1),
    pupil_size_right DECIMAL(3, 1),
    pupil_reaction_left VARCHAR(20),
    pupil_reaction_right VARCHAR(20),
    
    -- Hemodynamic
    central_venous_pressure INTEGER,
    cardiac_output DECIMAL(4, 2),
    systemic_vascular_resistance INTEGER,
    
    -- Fluid Balance
    urine_output INTEGER, -- ml/hour
    fluid_intake INTEGER, -- ml/hour
    
    -- Laboratory (Point of Care)
    blood_glucose INTEGER,
    lactate DECIMAL(4, 2),
    
    -- Alerts
    is_critical BOOLEAN DEFAULT false,
    critical_parameters TEXT[],
    alert_sent BOOLEAN DEFAULT false,
    
    -- Notes
    notes TEXT,
    
    CONSTRAINT check_vitals_bp CHECK (
        blood_pressure_systolic IS NULL OR 
        (blood_pressure_systolic >= 40 AND blood_pressure_systolic <= 300)
    ),
    CONSTRAINT check_vitals_hr CHECK (heart_rate IS NULL OR (heart_rate >= 20 AND heart_rate <= 300)),
    CONSTRAINT check_vitals_temp CHECK (temperature IS NULL OR (temperature >= 32.0 AND temperature <= 45.0)),
    CONSTRAINT check_vitals_spo2 CHECK (oxygen_saturation IS NULL OR (oxygen_saturation >= 50 AND oxygen_saturation <= 100)),
    CONSTRAINT check_vitals_fio2 CHECK (fio2 IS NULL OR (fio2 >= 21 AND fio2 <= 100)),
    CONSTRAINT check_vitals_gcs CHECK (glasgow_coma_scale IS NULL OR (glasgow_coma_scale >= 3 AND glasgow_coma_scale <= 15))
);

-- Indexes for ICU vitals
CREATE INDEX idx_icu_vitals_admission ON clinical.icu_vitals(admission_id);
CREATE INDEX idx_icu_vitals_patient ON clinical.icu_vitals(patient_id);
CREATE INDEX idx_icu_vitals_recorded ON clinical.icu_vitals(recorded_at);
CREATE INDEX idx_icu_vitals_critical ON clinical.icu_vitals(is_critical);

-- Partitioning by date for performance (optional, for high-volume data)
-- CREATE TABLE clinical.icu_vitals_2025_01 PARTITION OF clinical.icu_vitals
-- FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- ============================================
-- ICU MEDICATIONS
-- ============================================

CREATE TABLE clinical.icu_medications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- References
    admission_id UUID REFERENCES clinical.icu_admissions(id) ON DELETE CASCADE NOT NULL,
    patient_id UUID REFERENCES clinical.patients(id) NOT NULL,
    
    -- Medication
    medicine_id UUID, -- Reference to inventory.medicines
    medicine_name VARCHAR(255) NOT NULL,
    
    -- Dosage
    dose VARCHAR(100) NOT NULL,
    dose_unit VARCHAR(50) NOT NULL,
    route route_enum NOT NULL,
    
    -- Frequency
    frequency VARCHAR(100) NOT NULL,
    
    -- Infusion Details (for continuous medications)
    is_continuous_infusion BOOLEAN DEFAULT false,
    infusion_rate VARCHAR(100),
    infusion_rate_unit VARCHAR(50),
    
    -- Timing
    start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    
    -- Administration
    administered_by UUID REFERENCES clinical.staff(id) NOT NULL,
    administered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    -- Verification
    verified_by UUID REFERENCES clinical.staff(id),
    double_check_required BOOLEAN DEFAULT false,
    double_checked_by UUID REFERENCES clinical.staff(id),
    
    -- Status
    is_stat BOOLEAN DEFAULT false,
    is_prn BOOLEAN DEFAULT false, -- As needed
    is_stopped BOOLEAN DEFAULT false,
    stop_reason TEXT,
    
    -- Notes
    notes TEXT,
    
    CONSTRAINT check_med_times CHECK (end_time IS NULL OR end_time >= start_time)
);

-- Indexes for ICU medications
CREATE INDEX idx_icu_meds_admission ON clinical.icu_medications(admission_id);
CREATE INDEX idx_icu_meds_patient ON clinical.icu_medications(patient_id);
CREATE INDEX idx_icu_meds_time ON clinical.icu_medications(administered_at);

-- ============================================
-- CRITICAL ALERTS
-- ============================================

CREATE TABLE clinical.critical_alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Alert Details
    alert_type VARCHAR(50) NOT NULL, -- vital_sign, lab_result, medication, equipment
    severity VARCHAR(20) NOT NULL, -- warning, critical, emergency
    
    -- Patient
    patient_id UUID REFERENCES clinical.patients(id) NOT NULL,
    
    -- Context
    emergency_case_id UUID REFERENCES clinical.emergency_cases(id),
    icu_admission_id UUID REFERENCES clinical.icu_admissions(id),
    
    -- Alert Information
    alert_message TEXT NOT NULL,
    alert_details JSONB,
    
    -- Parameters
    parameter_name VARCHAR(100),
    parameter_value TEXT,
    threshold_value TEXT,
    
    -- Response
    is_acknowledged BOOLEAN DEFAULT false NOT NULL,
    acknowledged_by UUID REFERENCES core.users(id),
    acknowledged_at TIMESTAMP,
    
    is_resolved BOOLEAN DEFAULT false NOT NULL,
    resolved_by UUID REFERENCES core.users(id),
    resolved_at TIMESTAMP,
    resolution_notes TEXT,
    
    -- Notifications
    notified_users UUID[],
    notification_sent_at TIMESTAMP,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_alert_severity CHECK (severity IN ('warning', 'critical', 'emergency'))
);

-- Indexes for critical alerts
CREATE INDEX idx_alerts_patient ON clinical.critical_alerts(patient_id);
CREATE INDEX idx_alerts_type ON clinical.critical_alerts(alert_type);
CREATE INDEX idx_alerts_severity ON clinical.critical_alerts(severity);
CREATE INDEX idx_alerts_acknowledged ON clinical.critical_alerts(is_acknowledged);
CREATE INDEX idx_alerts_resolved ON clinical.critical_alerts(is_resolved);
CREATE INDEX idx_alerts_created ON clinical.critical_alerts(created_at);

-- Index for unresolved critical alerts (most important)
CREATE INDEX idx_alerts_unresolved_critical ON clinical.critical_alerts(severity, created_at)
WHERE is_resolved = false AND severity IN ('critical', 'emergency');

-- ============================================
-- FUNCTIONS
-- ============================================

-- Function to generate emergency case number
CREATE OR REPLACE FUNCTION clinical.generate_emergency_case_number()
RETURNS VARCHAR AS $$
DECLARE
    year_part VARCHAR(4);
    count_part INTEGER;
    new_number VARCHAR(20);
BEGIN
    year_part := TO_CHAR(CURRENT_DATE, 'YYYY');
    
    SELECT COUNT(*) + 1 INTO count_part
    FROM clinical.emergency_cases
    WHERE case_number LIKE 'EMR-' || year_part || '-%';
    
    new_number := 'EMR-' || year_part || '-' || LPAD(count_part::TEXT, 6, '0');
    
    RETURN new_number;
END;
$$ LANGUAGE plpgsql;

-- Function to generate ICU admission number
CREATE OR REPLACE FUNCTION clinical.generate_icu_admission_number()
RETURNS VARCHAR AS $$
DECLARE
    year_part VARCHAR(4);
    count_part INTEGER;
    new_number VARCHAR(20);
BEGIN
    year_part := TO_CHAR(CURRENT_DATE, 'YYYY');
    
    SELECT COUNT(*) + 1 INTO count_part
    FROM clinical.icu_admissions
    WHERE admission_number LIKE 'ICU-' || year_part || '-%';
    
    new_number := 'ICU-' || year_part || '-' || LPAD(count_part::TEXT, 6, '0');
    
    RETURN new_number;
END;
$$ LANGUAGE plpgsql;

-- Function to check critical vital signs
CREATE OR REPLACE FUNCTION clinical.check_critical_vitals()
RETURNS TRIGGER AS $$
DECLARE
    critical_params TEXT[] := ARRAY[]::TEXT[];
    alert_message TEXT;
BEGIN
    -- Check blood pressure
    IF NEW.blood_pressure_systolic < 90 OR NEW.blood_pressure_systolic > 180 THEN
        critical_params := array_append(critical_params, 'Blood Pressure: ' || NEW.blood_pressure_systolic || '/' || NEW.blood_pressure_diastolic);
    END IF;
    
    -- Check heart rate
    IF NEW.heart_rate < 40 OR NEW.heart_rate > 140 THEN
        critical_params := array_append(critical_params, 'Heart Rate: ' || NEW.heart_rate);
    END IF;
    
    -- Check oxygen saturation
    IF NEW.oxygen_saturation < 90 THEN
        critical_params := array_append(critical_params, 'SpO2: ' || NEW.oxygen_saturation || '%');
    END IF;
    
    -- Check temperature
    IF NEW.temperature < 35.0 OR NEW.temperature > 39.5 THEN
        critical_params := array_append(critical_params, 'Temperature: ' || NEW.temperature || '°C');
    END IF;
    
    -- If critical parameters found, create alert
    IF array_length(critical_params, 1) > 0 THEN
        NEW.is_critical := true;
        NEW.critical_parameters := critical_params;
        
        alert_message := 'Critical vital signs detected: ' || array_to_string(critical_params, ', ');
        
        INSERT INTO clinical.critical_alerts (
            alert_type,
            severity,
            patient_id,
            icu_admission_id,
            alert_message,
            parameter_name,
            parameter_value
        ) VALUES (
            'vital_sign',
            'critical',
            NEW.patient_id,
            NEW.admission_id,
            alert_message,
            'vitals',
            array_to_string(critical_params, '; ')
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update bed status on ICU admission
CREATE OR REPLACE FUNCTION clinical.update_bed_on_admission()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE clinical.icu_beds
        SET status = 'occupied',
            current_patient_id = NEW.patient_id,
            occupied_since = NEW.admission_date,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.bed_id;
    ELSIF TG_OP = 'UPDATE' AND NEW.status != OLD.status AND NEW.status IN ('discharged', 'transferred', 'deceased') THEN
        UPDATE clinical.icu_beds
        SET status = 'cleaning',
            current_patient_id = NULL,
            occupied_since = NULL,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.bed_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-generate emergency case number
CREATE OR REPLACE FUNCTION clinical.set_emergency_case_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.case_number IS NULL THEN
        NEW.case_number := clinical.generate_emergency_case_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_emergency_case_number
    BEFORE INSERT ON clinical.emergency_cases
    FOR EACH ROW
    EXECUTE FUNCTION clinical.set_emergency_case_number();

-- Auto-generate ICU admission number
CREATE OR REPLACE FUNCTION clinical.set_icu_admission_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.admission_number IS NULL THEN
        NEW.admission_number := clinical.generate_icu_admission_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_icu_admission_number
    BEFORE INSERT ON clinical.icu_admissions
    FOR EACH ROW
    EXECUTE FUNCTION clinical.set_icu_admission_number();

-- Check critical vitals
CREATE TRIGGER trigger_check_critical_vitals
    BEFORE INSERT ON clinical.icu_vitals
    FOR EACH ROW
    EXECUTE FUNCTION clinical.check_critical_vitals();

-- Update bed status
CREATE TRIGGER trigger_update_bed_status
    AFTER INSERT OR UPDATE ON clinical.icu_admissions
    FOR EACH ROW
    EXECUTE FUNCTION clinical.update_bed_on_admission();

-- Updated_at triggers
CREATE TRIGGER update_emergency_cases_updated_at
    BEFORE UPDATE ON clinical.emergency_cases
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_icu_beds_updated_at
    BEFORE UPDATE ON clinical.icu_beds
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_icu_admissions_updated_at
    BEFORE UPDATE ON clinical.icu_admissions
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

-- Audit triggers (CRITICAL - life-threatening situations)
CREATE TRIGGER audit_emergency_cases_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.emergency_cases
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_icu_admissions_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.icu_admissions
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_icu_vitals_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.icu_vitals
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_icu_medications_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.icu_medications
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON TABLE clinical.emergency_cases IS 'Emergency department cases - CRITICAL: Life-threatening situations';
COMMENT ON TABLE clinical.icu_beds IS 'ICU bed management and availability';
COMMENT ON TABLE clinical.icu_admissions IS 'ICU patient admissions - CRITICAL care';
COMMENT ON TABLE clinical.icu_vitals IS 'Real-time vital signs monitoring - CRITICAL for patient safety';
COMMENT ON TABLE clinical.icu_medications IS 'ICU medication administration - CRITICAL: Dosing errors can be fatal';
COMMENT ON TABLE clinical.critical_alerts IS 'Critical patient alerts - IMMEDIATE response required';
COMMENT ON FUNCTION clinical.check_critical_vitals IS 'Automatically detects critical vital signs - LIFE-SAVING';

-- ============================================
-- SCHEMA VERSION
-- ============================================

INSERT INTO core.schema_versions (version, description) VALUES
    ('1.6.0', 'Emergency and ICU management schema with critical monitoring');

-- ============================================
-- END OF EMERGENCY & ICU SCHEMA
-- ============================================
