-- ============================================
-- HOSPITAL MANAGEMENT SYSTEM - APPOINTMENTS & CONSULTATIONS SCHEMA
-- ============================================
-- ⚠️ CRITICAL: Appointment scheduling affects patient care
-- Proper validation and conflict detection required

SET search_path TO clinical, core, audit, public;

-- ============================================
-- APPOINTMENTS
-- ============================================

CREATE TABLE clinical.appointments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    appointment_number VARCHAR(20) UNIQUE NOT NULL,
    
    -- Parties Involved
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    doctor_id UUID REFERENCES clinical.doctors(id) NOT NULL,
    department_id UUID REFERENCES core.departments(id),
    
    -- Scheduling Information
    appointment_date DATE NOT NULL,
    appointment_time TIME NOT NULL,
    duration_minutes INTEGER DEFAULT 30 NOT NULL,
    end_time TIME GENERATED ALWAYS AS (appointment_time + (duration_minutes || ' minutes')::INTERVAL) STORED,
    
    -- Type and Priority
    appointment_type appointment_type_enum NOT NULL,
    priority priority_enum DEFAULT 'normal' NOT NULL,
    
    -- Status Tracking
    status appointment_status_enum DEFAULT 'scheduled' NOT NULL,
    
    -- Check-in/Check-out
    check_in_time TIMESTAMP,
    check_in_by UUID REFERENCES core.users(id),
    consultation_start_time TIMESTAMP,
    consultation_end_time TIMESTAMP,
    actual_duration_minutes INTEGER,
    
    -- Clinical Information
    reason_for_visit TEXT NOT NULL,
    symptoms TEXT[],
    chief_complaint TEXT,
    is_first_visit BOOLEAN DEFAULT false NOT NULL,
    is_follow_up BOOLEAN DEFAULT false NOT NULL,
    follow_up_for UUID REFERENCES clinical.appointments(id),
    
    -- Referral
    referred_by VARCHAR(255),
    referral_notes TEXT,
    
    -- Cancellation/Rescheduling
    cancelled_at TIMESTAMP,
    cancelled_by UUID REFERENCES core.users(id),
    cancellation_reason TEXT,
    rescheduled_from UUID REFERENCES clinical.appointments(id),
    rescheduled_to UUID REFERENCES clinical.appointments(id),
    
    -- Notifications
    reminder_sent BOOLEAN DEFAULT false NOT NULL,
    reminder_sent_at TIMESTAMP,
    confirmation_sent BOOLEAN DEFAULT false NOT NULL,
    confirmation_sent_at TIMESTAMP,
    
    -- Queue Management
    queue_number INTEGER,
    estimated_wait_time INTEGER, -- in minutes
    
    -- Billing
    consultation_fee DECIMAL(10, 2),
    is_paid BOOLEAN DEFAULT false NOT NULL,
    payment_id UUID,
    
    -- Notes
    reception_notes TEXT,
    special_instructions TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    updated_by UUID REFERENCES core.users(id),
    
    -- Constraints
    CONSTRAINT check_appointment_future CHECK (
        appointment_date >= CURRENT_DATE OR 
        (appointment_date = CURRENT_DATE AND appointment_time >= CURRENT_TIME)
    ),
    CONSTRAINT check_duration CHECK (duration_minutes > 0 AND duration_minutes <= 480),
    CONSTRAINT check_consultation_times CHECK (
        consultation_end_time IS NULL OR 
        consultation_end_time > consultation_start_time
    ),
    CONSTRAINT check_fee CHECK (consultation_fee >= 0),
    CONSTRAINT unique_doctor_slot UNIQUE(doctor_id, appointment_date, appointment_time)
);

-- Indexes for appointments
CREATE INDEX idx_appointments_patient ON clinical.appointments(patient_id);
CREATE INDEX idx_appointments_doctor ON clinical.appointments(doctor_id);
CREATE INDEX idx_appointments_date ON clinical.appointments(appointment_date);
CREATE INDEX idx_appointments_datetime ON clinical.appointments(appointment_date, appointment_time);
CREATE INDEX idx_appointments_status ON clinical.appointments(status);
CREATE INDEX idx_appointments_type ON clinical.appointments(appointment_type);
CREATE INDEX idx_appointments_number ON clinical.appointments(appointment_number);
CREATE INDEX idx_appointments_created_at ON clinical.appointments(created_at);

-- Composite index for availability checking
CREATE INDEX idx_appointments_doctor_date_status ON clinical.appointments(
    doctor_id, appointment_date, status
) WHERE status NOT IN ('cancelled', 'no_show');

-- ============================================
-- CONSULTATIONS
-- ============================================

CREATE TABLE clinical.consultations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- References
    appointment_id UUID REFERENCES clinical.appointments(id),
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    doctor_id UUID REFERENCES clinical.doctors(id) NOT NULL,
    
    -- Consultation Details
    consultation_date DATE DEFAULT CURRENT_DATE NOT NULL,
    consultation_time TIME DEFAULT CURRENT_TIME NOT NULL,
    duration_minutes INTEGER,
    
    -- Vital Signs
    blood_pressure_systolic INTEGER,
    blood_pressure_diastolic INTEGER,
    pulse_rate INTEGER,
    temperature DECIMAL(4, 1),
    respiratory_rate INTEGER,
    oxygen_saturation DECIMAL(5, 2),
    weight DECIMAL(5, 2),
    height DECIMAL(5, 2),
    bmi DECIMAL(4, 2) GENERATED ALWAYS AS (
        CASE 
            WHEN height > 0 THEN ROUND((weight / ((height/100) * (height/100)))::NUMERIC, 2)
            ELSE NULL
        END
    ) STORED,
    
    -- Clinical Assessment
    chief_complaint TEXT NOT NULL,
    history_of_present_illness TEXT,
    review_of_systems TEXT,
    physical_examination TEXT,
    
    -- Diagnosis
    provisional_diagnosis TEXT,
    final_diagnosis TEXT,
    icd_10_codes TEXT[],
    snomed_codes TEXT[],
    differential_diagnosis TEXT[],
    
    -- Assessment
    clinical_impression TEXT,
    severity_assessment priority_enum,
    
    -- Treatment Plan
    treatment_plan TEXT,
    medications_prescribed BOOLEAN DEFAULT false,
    lab_tests_ordered BOOLEAN DEFAULT false,
    imaging_ordered BOOLEAN DEFAULT false,
    procedures_recommended TEXT[],
    
    -- Follow-up
    follow_up_required BOOLEAN DEFAULT false NOT NULL,
    follow_up_date DATE,
    follow_up_instructions TEXT,
    
    -- Referrals
    referral_required BOOLEAN DEFAULT false,
    referred_to_doctor_id UUID REFERENCES clinical.doctors(id),
    referred_to_department_id UUID REFERENCES core.departments(id),
    referral_reason TEXT,
    
    -- Clinical Notes
    clinical_notes TEXT,
    private_notes TEXT, -- Only visible to the doctor
    patient_education TEXT,
    
    -- Attachments
    attachment_urls TEXT[],
    
    -- Status
    is_completed BOOLEAN DEFAULT false NOT NULL,
    completed_at TIMESTAMP,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    -- Constraints
    CONSTRAINT check_bp_systolic CHECK (blood_pressure_systolic IS NULL OR (blood_pressure_systolic >= 60 AND blood_pressure_systolic <= 250)),
    CONSTRAINT check_bp_diastolic CHECK (blood_pressure_diastolic IS NULL OR (blood_pressure_diastolic >= 40 AND blood_pressure_diastolic <= 150)),
    CONSTRAINT check_pulse CHECK (pulse_rate IS NULL OR (pulse_rate >= 30 AND pulse_rate <= 250)),
    CONSTRAINT check_temperature CHECK (temperature IS NULL OR (temperature >= 35.0 AND temperature <= 43.0)),
    CONSTRAINT check_respiratory CHECK (respiratory_rate IS NULL OR (respiratory_rate >= 8 AND respiratory_rate <= 60)),
    CONSTRAINT check_oxygen CHECK (oxygen_saturation IS NULL OR (oxygen_saturation >= 70 AND oxygen_saturation <= 100)),
    CONSTRAINT check_weight CHECK (weight IS NULL OR (weight > 0 AND weight < 500)),
    CONSTRAINT check_height CHECK (height IS NULL OR (height > 0 AND height < 300))
);

-- Indexes for consultations
CREATE INDEX idx_consultations_appointment ON clinical.consultations(appointment_id);
CREATE INDEX idx_consultations_patient ON clinical.consultations(patient_id);
CREATE INDEX idx_consultations_doctor ON clinical.consultations(doctor_id);
CREATE INDEX idx_consultations_date ON clinical.consultations(consultation_date);
CREATE INDEX idx_consultations_completed ON clinical.consultations(is_completed);

-- Full-text search on clinical notes
CREATE INDEX idx_consultations_notes_fts ON clinical.consultations USING gin(
    to_tsvector('english', 
        COALESCE(chief_complaint, '') || ' ' || 
        COALESCE(clinical_notes, '') || ' ' ||
        COALESCE(final_diagnosis, '')
    )
);

-- ============================================
-- PRESCRIPTIONS
-- ============================================

CREATE TYPE prescription_status_enum AS ENUM ('draft', 'active', 'dispensed', 'completed', 'cancelled', 'expired');

CREATE TABLE clinical.prescriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    prescription_number VARCHAR(20) UNIQUE NOT NULL,
    
    -- References
    consultation_id UUID REFERENCES clinical.consultations(id),
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    doctor_id UUID REFERENCES clinical.doctors(id) NOT NULL,
    
    -- Status
    status prescription_status_enum DEFAULT 'draft' NOT NULL,
    
    -- Validity
    prescribed_date DATE DEFAULT CURRENT_DATE NOT NULL,
    valid_until DATE,
    
    -- Pharmacy Information
    dispensed_by UUID REFERENCES clinical.staff(id),
    dispensed_at TIMESTAMP,
    pharmacy_notes TEXT,
    
    -- Digital Signature
    is_signed BOOLEAN DEFAULT false NOT NULL,
    signed_at TIMESTAMP,
    signature_hash VARCHAR(255),
    signature_data BYTEA,
    
    -- Instructions
    general_instructions TEXT,
    dietary_instructions TEXT,
    precautions TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_validity CHECK (valid_until IS NULL OR valid_until >= prescribed_date)
);

-- Indexes for prescriptions
CREATE INDEX idx_prescriptions_number ON clinical.prescriptions(prescription_number);
CREATE INDEX idx_prescriptions_patient ON clinical.prescriptions(patient_id);
CREATE INDEX idx_prescriptions_doctor ON clinical.prescriptions(doctor_id);
CREATE INDEX idx_prescriptions_consultation ON clinical.prescriptions(consultation_id);
CREATE INDEX idx_prescriptions_status ON clinical.prescriptions(status);
CREATE INDEX idx_prescriptions_date ON clinical.prescriptions(prescribed_date);

-- ============================================
-- PRESCRIPTION ITEMS
-- ============================================

CREATE TYPE dosage_unit_enum AS ENUM ('mg', 'ml', 'mcg', 'g', 'tablet', 'capsule', 'drops', 'puff', 'unit', 'iu');
CREATE TYPE route_enum AS ENUM ('oral', 'injection', 'topical', 'inhalation', 'rectal', 'nasal', 'ophthalmic', 'otic', 'sublingual', 'transdermal');
CREATE TYPE food_relation_enum AS ENUM ('before_food', 'after_food', 'with_food', 'empty_stomach', 'anytime');

CREATE TABLE clinical.prescription_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    prescription_id UUID REFERENCES clinical.prescriptions(id) ON DELETE CASCADE NOT NULL,
    
    -- Medicine Information (will reference inventory.medicines later)
    medicine_id UUID, -- Reference to be added
    medicine_name VARCHAR(255) NOT NULL,
    generic_name VARCHAR(255),
    
    -- Dosage Information
    dosage VARCHAR(100) NOT NULL,
    dosage_unit dosage_unit_enum NOT NULL,
    strength VARCHAR(50),
    
    -- Frequency
    frequency VARCHAR(100) NOT NULL, -- "1-0-1", "twice daily", "every 6 hours"
    frequency_times_per_day INTEGER,
    duration_days INTEGER NOT NULL,
    
    -- Administration
    route route_enum NOT NULL,
    food_relation food_relation_enum,
    timing_instructions TEXT,
    special_instructions TEXT,
    
    -- Quantity
    quantity_prescribed INTEGER NOT NULL,
    quantity_dispensed INTEGER DEFAULT 0 NOT NULL,
    
    -- Refills
    refills_allowed INTEGER DEFAULT 0 NOT NULL,
    refills_remaining INTEGER DEFAULT 0 NOT NULL,
    
    -- Substitution
    allow_substitution BOOLEAN DEFAULT true NOT NULL,
    substituted_with UUID, -- Reference to another medicine
    substitution_reason TEXT,
    
    -- Status
    is_dispensed BOOLEAN DEFAULT false NOT NULL,
    dispensed_at TIMESTAMP,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_quantity CHECK (quantity_prescribed > 0),
    CONSTRAINT check_duration CHECK (duration_days > 0 AND duration_days <= 365),
    CONSTRAINT check_refills CHECK (refills_allowed >= 0 AND refills_remaining >= 0),
    CONSTRAINT check_dispensed_quantity CHECK (quantity_dispensed <= quantity_prescribed)
);

-- Indexes for prescription items
CREATE INDEX idx_prescription_items_prescription ON clinical.prescription_items(prescription_id);
CREATE INDEX idx_prescription_items_medicine ON clinical.prescription_items(medicine_id);
CREATE INDEX idx_prescription_items_dispensed ON clinical.prescription_items(is_dispensed);

-- ============================================
-- APPOINTMENT QUEUE
-- ============================================

CREATE TABLE clinical.appointment_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    appointment_id UUID REFERENCES clinical.appointments(id) ON DELETE CASCADE NOT NULL,
    doctor_id UUID REFERENCES clinical.doctors(id) NOT NULL,
    
    -- Queue Information
    queue_date DATE DEFAULT CURRENT_DATE NOT NULL,
    queue_number INTEGER NOT NULL,
    priority priority_enum DEFAULT 'normal' NOT NULL,
    
    -- Status
    status VARCHAR(20) DEFAULT 'waiting' NOT NULL, -- waiting, in_progress, completed, skipped
    
    -- Timing
    added_to_queue_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    called_at TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    
    -- Wait Time Tracking
    estimated_wait_minutes INTEGER,
    actual_wait_minutes INTEGER,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_queue_number CHECK (queue_number > 0),
    CONSTRAINT check_status CHECK (status IN ('waiting', 'in_progress', 'completed', 'skipped', 'cancelled')),
    CONSTRAINT unique_doctor_queue_number UNIQUE(doctor_id, queue_date, queue_number)
);

CREATE INDEX idx_queue_appointment ON clinical.appointment_queue(appointment_id);
CREATE INDEX idx_queue_doctor_date ON clinical.appointment_queue(doctor_id, queue_date);
CREATE INDEX idx_queue_status ON clinical.appointment_queue(status);

-- ============================================
-- FUNCTIONS FOR APPOINTMENT MANAGEMENT
-- ============================================

-- Function to generate appointment number
CREATE OR REPLACE FUNCTION clinical.generate_appointment_number()
RETURNS VARCHAR AS $$
DECLARE
    year_part VARCHAR(4);
    count_part INTEGER;
    new_number VARCHAR(20);
BEGIN
    year_part := TO_CHAR(CURRENT_DATE, 'YYYY');
    
    SELECT COUNT(*) + 1 INTO count_part
    FROM clinical.appointments
    WHERE appointment_number LIKE 'APT-' || year_part || '-%';
    
    new_number := 'APT-' || year_part || '-' || LPAD(count_part::TEXT, 6, '0');
    
    RETURN new_number;
END;
$$ LANGUAGE plpgsql;

-- Function to check doctor availability
CREATE OR REPLACE FUNCTION clinical.check_doctor_availability(
    p_doctor_id UUID,
    p_date DATE,
    p_time TIME,
    p_duration INTEGER DEFAULT 30
)
RETURNS BOOLEAN AS $$
DECLARE
    v_end_time TIME;
    v_conflict_count INTEGER;
    v_schedule_exists BOOLEAN;
    v_on_leave BOOLEAN;
BEGIN
    v_end_time := p_time + (p_duration || ' minutes')::INTERVAL;
    
    -- Check if doctor has schedule for this day
    SELECT EXISTS(
        SELECT 1 FROM clinical.doctor_schedules
        WHERE doctor_id = p_doctor_id
        AND day_of_week = EXTRACT(DOW FROM p_date)
        AND is_active = true
        AND p_time >= start_time
        AND v_end_time <= end_time
        AND (effective_from IS NULL OR effective_from <= p_date)
        AND (effective_until IS NULL OR effective_until >= p_date)
    ) INTO v_schedule_exists;
    
    IF NOT v_schedule_exists THEN
        RETURN false;
    END IF;
    
    -- Check if doctor is on leave
    SELECT EXISTS(
        SELECT 1 FROM clinical.doctor_leaves
        WHERE doctor_id = p_doctor_id
        AND status = 'approved'
        AND p_date BETWEEN from_date AND to_date
    ) INTO v_on_leave;
    
    IF v_on_leave THEN
        RETURN false;
    END IF;
    
    -- Check for conflicting appointments
    SELECT COUNT(*) INTO v_conflict_count
    FROM clinical.appointments
    WHERE doctor_id = p_doctor_id
    AND appointment_date = p_date
    AND status NOT IN ('cancelled', 'no_show')
    AND (
        (appointment_time <= p_time AND end_time > p_time) OR
        (appointment_time < v_end_time AND end_time >= v_end_time) OR
        (appointment_time >= p_time AND end_time <= v_end_time)
    );
    
    RETURN v_conflict_count = 0;
END;
$$ LANGUAGE plpgsql;

-- Function to generate prescription number
CREATE OR REPLACE FUNCTION clinical.generate_prescription_number()
RETURNS VARCHAR AS $$
DECLARE
    year_part VARCHAR(4);
    count_part INTEGER;
    new_number VARCHAR(20);
BEGIN
    year_part := TO_CHAR(CURRENT_DATE, 'YYYY');
    
    SELECT COUNT(*) + 1 INTO count_part
    FROM clinical.prescriptions
    WHERE prescription_number LIKE 'RX-' || year_part || '-%';
    
    new_number := 'RX-' || year_part || '-' || LPAD(count_part::TEXT, 6, '0');
    
    RETURN new_number;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS
-- ============================================

-- Trigger to auto-generate appointment number
CREATE OR REPLACE FUNCTION clinical.set_appointment_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.appointment_number IS NULL THEN
        NEW.appointment_number := clinical.generate_appointment_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_appointment_number
    BEFORE INSERT ON clinical.appointments
    FOR EACH ROW
    EXECUTE FUNCTION clinical.set_appointment_number();

-- Trigger to auto-generate prescription number
CREATE OR REPLACE FUNCTION clinical.set_prescription_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.prescription_number IS NULL THEN
        NEW.prescription_number := clinical.generate_prescription_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_prescription_number
    BEFORE INSERT ON clinical.prescriptions
    FOR EACH ROW
    EXECUTE FUNCTION clinical.set_prescription_number();

-- Updated_at triggers
CREATE TRIGGER update_appointments_updated_at
    BEFORE UPDATE ON clinical.appointments
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_consultations_updated_at
    BEFORE UPDATE ON clinical.consultations
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_prescriptions_updated_at
    BEFORE UPDATE ON clinical.prescriptions
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

-- Audit triggers (CRITICAL)
CREATE TRIGGER audit_appointments_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.appointments
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_consultations_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.consultations
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_prescriptions_changes
    AFTER INSERT OR UPDATE OR DELETE ON clinical.prescriptions
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON TABLE clinical.appointments IS 'Patient appointments - Critical for scheduling';
COMMENT ON TABLE clinical.consultations IS 'Clinical consultations - Contains PHI';
COMMENT ON TABLE clinical.prescriptions IS 'Medical prescriptions - Controlled substance tracking';
COMMENT ON TABLE clinical.prescription_items IS 'Individual prescription items';
COMMENT ON FUNCTION clinical.check_doctor_availability IS 'Validates doctor availability for appointment booking';

-- ============================================
-- SCHEMA VERSION
-- ============================================

INSERT INTO core.schema_versions (version, description) VALUES
    ('1.2.0', 'Appointments, consultations, and prescriptions schema');

-- ============================================
-- END OF APPOINTMENTS & CONSULTATIONS SCHEMA
-- ============================================
