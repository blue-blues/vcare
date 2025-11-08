-- ============================================
-- HOSPITAL MANAGEMENT SYSTEM - BILLING & INSURANCE SCHEMA
-- ============================================
-- ⚠️ CRITICAL: Financial accuracy is essential
-- All transactions must be audited and reconciled

SET search_path TO billing, clinical, inventory, core, audit, public;

-- Create billing schema if not exists
CREATE SCHEMA IF NOT EXISTS billing;

-- ============================================
-- CUSTOM TYPES
-- ============================================

CREATE TYPE bill_type_enum AS ENUM (
    'opd',
    'ipd',
    'emergency',
    'pharmacy',
    'laboratory',
    'imaging',
    'procedure',
    'consultation',
    'other'
);

CREATE TYPE bill_status_enum AS ENUM (
    'draft',
    'pending',
    'partial',
    'paid',
    'cancelled',
    'refunded',
    'written_off'
);

CREATE TYPE payment_method_enum AS ENUM (
    'cash',
    'card',
    'check',
    'bank_transfer',
    'insurance',
    'online',
    'upi',
    'wallet',
    'other'
);

CREATE TYPE payment_status_enum AS ENUM (
    'pending',
    'processing',
    'completed',
    'failed',
    'refunded',
    'cancelled'
);

CREATE TYPE claim_status_enum AS ENUM (
    'draft',
    'submitted',
    'under_review',
    'approved',
    'partially_approved',
    'rejected',
    'appealed',
    'paid'
);

-- ============================================
-- BILLS
-- ============================================

CREATE TABLE billing.bills (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    bill_number VARCHAR(20) UNIQUE NOT NULL,
    invoice_number VARCHAR(20) UNIQUE,
    
    -- Patient
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    
    -- Bill Type
    bill_type bill_type_enum NOT NULL,
    
    -- References
    consultation_id UUID REFERENCES clinical.consultations(id),
    appointment_id UUID REFERENCES clinical.appointments(id),
    admission_id UUID, -- Will reference admissions table
    
    -- Amounts
    subtotal DECIMAL(12, 2) NOT NULL,
    tax_amount DECIMAL(10, 2) DEFAULT 0 NOT NULL,
    discount_amount DECIMAL(10, 2) DEFAULT 0 NOT NULL,
    adjustment_amount DECIMAL(10, 2) DEFAULT 0 NOT NULL,
    total_amount DECIMAL(12, 2) NOT NULL,
    
    -- Payments
    paid_amount DECIMAL(12, 2) DEFAULT 0 NOT NULL,
    balance_amount DECIMAL(12, 2) GENERATED ALWAYS AS (total_amount - paid_amount) STORED,
    
    -- Insurance
    insurance_claim_id UUID,
    insurance_covered_amount DECIMAL(12, 2) DEFAULT 0 NOT NULL,
    patient_copay_amount DECIMAL(12, 2) DEFAULT 0 NOT NULL,
    
    -- Status
    status bill_status_enum DEFAULT 'draft' NOT NULL,
    
    -- Dates
    bill_date DATE DEFAULT CURRENT_DATE NOT NULL,
    due_date DATE,
    paid_date DATE,
    
    -- Discount
    discount_reason TEXT,
    discount_approved_by UUID REFERENCES core.users(id),
    
    -- Notes
    notes TEXT,
    terms_and_conditions TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    updated_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_bill_amounts CHECK (
        subtotal >= 0 AND 
        tax_amount >= 0 AND 
        discount_amount >= 0 AND 
        total_amount >= 0 AND
        paid_amount >= 0 AND
        paid_amount <= total_amount AND
        insurance_covered_amount >= 0 AND
        patient_copay_amount >= 0
    ),
    CONSTRAINT check_bill_dates CHECK (due_date IS NULL OR due_date >= bill_date)
);

-- Indexes for bills
CREATE INDEX idx_bills_number ON billing.bills(bill_number);
CREATE INDEX idx_bills_patient ON billing.bills(patient_id);
CREATE INDEX idx_bills_type ON billing.bills(bill_type);
CREATE INDEX idx_bills_status ON billing.bills(status);
CREATE INDEX idx_bills_date ON billing.bills(bill_date);
CREATE INDEX idx_bills_due_date ON billing.bills(due_date);
CREATE INDEX idx_bills_balance ON billing.bills(balance_amount) WHERE balance_amount > 0;

-- ============================================
-- BILL ITEMS
-- ============================================

CREATE TABLE billing.bill_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID REFERENCES billing.bills(id) ON DELETE CASCADE NOT NULL,
    
    -- Item Information
    item_type VARCHAR(50) NOT NULL, -- consultation, procedure, medicine, lab_test, room_charge, etc.
    item_code VARCHAR(50),
    item_name VARCHAR(255) NOT NULL,
    description TEXT,
    
    -- Reference to actual item
    reference_type VARCHAR(50),
    reference_id UUID,
    
    -- Quantity and Pricing
    quantity INTEGER DEFAULT 1 NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    
    -- Discounts and Taxes
    discount_percentage DECIMAL(5, 2) DEFAULT 0 NOT NULL,
    discount_amount DECIMAL(10, 2) DEFAULT 0 NOT NULL,
    tax_percentage DECIMAL(5, 2) DEFAULT 0 NOT NULL,
    tax_amount DECIMAL(10, 2) DEFAULT 0 NOT NULL,
    
    -- Total
    total_amount DECIMAL(12, 2) NOT NULL,
    
    -- Insurance
    is_covered_by_insurance BOOLEAN DEFAULT false,
    insurance_approved_amount DECIMAL(10, 2) DEFAULT 0,
    
    -- Service Provider
    performed_by UUID REFERENCES core.users(id),
    performed_date DATE,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_item_quantity CHECK (quantity > 0),
    CONSTRAINT check_item_prices CHECK (
        unit_price >= 0 AND 
        discount_amount >= 0 AND 
        tax_amount >= 0 AND 
        total_amount >= 0 AND
        insurance_approved_amount >= 0
    ),
    CONSTRAINT check_item_percentages CHECK (
        discount_percentage >= 0 AND 
        discount_percentage <= 100 AND 
        tax_percentage >= 0
    )
);

-- Indexes for bill items
CREATE INDEX idx_bill_items_bill ON billing.bill_items(bill_id);
CREATE INDEX idx_bill_items_type ON billing.bill_items(item_type);
CREATE INDEX idx_bill_items_reference ON billing.bill_items(reference_type, reference_id);

-- ============================================
-- PAYMENTS
-- ============================================

CREATE TABLE billing.payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    payment_number VARCHAR(20) UNIQUE NOT NULL,
    receipt_number VARCHAR(20) UNIQUE,
    
    -- Bill Reference
    bill_id UUID REFERENCES billing.bills(id) NOT NULL,
    patient_id UUID REFERENCES clinical.patients(id) NOT NULL,
    
    -- Payment Details
    amount DECIMAL(12, 2) NOT NULL,
    payment_method payment_method_enum NOT NULL,
    
    -- Payment Method Specific Details
    transaction_id VARCHAR(100),
    card_last_four VARCHAR(4),
    card_type VARCHAR(50), -- visa, mastercard, amex, etc.
    check_number VARCHAR(50),
    check_date DATE,
    bank_name VARCHAR(100),
    upi_id VARCHAR(100),
    
    -- Status
    status payment_status_enum DEFAULT 'pending' NOT NULL,
    
    -- Processing
    payment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    processed_date TIMESTAMP,
    
    -- Staff
    received_by UUID REFERENCES core.users(id) NOT NULL,
    
    -- Refund Information
    refund_amount DECIMAL(10, 2) DEFAULT 0,
    refund_date DATE,
    refund_reason TEXT,
    refunded_by UUID REFERENCES core.users(id),
    
    -- Notes
    notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_payment_amount CHECK (amount > 0),
    CONSTRAINT check_refund_amount CHECK (refund_amount >= 0 AND refund_amount <= amount)
);

-- Indexes for payments
CREATE INDEX idx_payments_number ON billing.payments(payment_number);
CREATE INDEX idx_payments_bill ON billing.payments(bill_id);
CREATE INDEX idx_payments_patient ON billing.payments(patient_id);
CREATE INDEX idx_payments_method ON billing.payments(payment_method);
CREATE INDEX idx_payments_status ON billing.payments(status);
CREATE INDEX idx_payments_date ON billing.payments(payment_date);
CREATE INDEX idx_payments_transaction ON billing.payments(transaction_id);

-- ============================================
-- INSURANCE CLAIMS
-- ============================================

CREATE TABLE billing.insurance_claims (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    claim_number VARCHAR(20) UNIQUE NOT NULL,
    
    -- Patient and Insurance
    patient_id UUID REFERENCES clinical.patients(id) ON DELETE CASCADE NOT NULL,
    insurance_id UUID REFERENCES clinical.patient_insurance(id) NOT NULL,
    
    -- Bill Reference
    bill_id UUID REFERENCES billing.bills(id),
    
    -- Claim Details
    claim_type VARCHAR(50) NOT NULL, -- medical, surgical, emergency, etc.
    diagnosis_codes TEXT[] NOT NULL,
    procedure_codes TEXT[],
    
    -- Amounts
    claimed_amount DECIMAL(12, 2) NOT NULL,
    approved_amount DECIMAL(12, 2) DEFAULT 0,
    rejected_amount DECIMAL(12, 2) DEFAULT 0,
    paid_amount DECIMAL(12, 2) DEFAULT 0,
    
    -- Status
    status claim_status_enum DEFAULT 'draft' NOT NULL,
    
    -- Dates
    service_date DATE NOT NULL,
    claim_date DATE DEFAULT CURRENT_DATE NOT NULL,
    submission_date DATE,
    approval_date DATE,
    payment_date DATE,
    
    -- Insurance Company Response
    insurance_reference_number VARCHAR(100),
    adjudication_notes TEXT,
    denial_reason TEXT,
    denial_code VARCHAR(50),
    
    -- Appeal Information
    is_appealed BOOLEAN DEFAULT false,
    appeal_date DATE,
    appeal_reason TEXT,
    appeal_outcome TEXT,
    
    -- Documents
    supporting_documents TEXT[],
    
    -- Processing
    submitted_by UUID REFERENCES core.users(id),
    processed_by UUID REFERENCES core.users(id),
    
    -- Notes
    notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_claim_amounts CHECK (
        claimed_amount > 0 AND 
        approved_amount >= 0 AND 
        rejected_amount >= 0 AND 
        paid_amount >= 0 AND
        approved_amount + rejected_amount <= claimed_amount AND
        paid_amount <= approved_amount
    ),
    CONSTRAINT check_claim_dates CHECK (
        claim_date >= service_date AND
        (submission_date IS NULL OR submission_date >= claim_date)
    )
);

-- Indexes for insurance claims
CREATE INDEX idx_claims_number ON billing.insurance_claims(claim_number);
CREATE INDEX idx_claims_patient ON billing.insurance_claims(patient_id);
CREATE INDEX idx_claims_insurance ON billing.insurance_claims(insurance_id);
CREATE INDEX idx_claims_bill ON billing.insurance_claims(bill_id);
CREATE INDEX idx_claims_status ON billing.insurance_claims(status);
CREATE INDEX idx_claims_date ON billing.insurance_claims(claim_date);

-- ============================================
-- PRICING CATALOG
-- ============================================

CREATE TABLE billing.service_pricing (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Service Details
    service_code VARCHAR(20) UNIQUE NOT NULL,
    service_name VARCHAR(255) NOT NULL,
    service_category VARCHAR(100) NOT NULL,
    description TEXT,
    
    -- Pricing
    base_price DECIMAL(10, 2) NOT NULL,
    emergency_price DECIMAL(10, 2),
    
    -- Insurance
    insurance_price DECIMAL(10, 2),
    cpt_code VARCHAR(20),
    hcpcs_code VARCHAR(20),
    
    -- Tax
    is_taxable BOOLEAN DEFAULT true,
    tax_percentage DECIMAL(5, 2) DEFAULT 0,
    
    -- Department
    department_id UUID REFERENCES core.departments(id),
    
    -- Status
    is_active BOOLEAN DEFAULT true NOT NULL,
    effective_from DATE DEFAULT CURRENT_DATE,
    effective_until DATE,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_pricing CHECK (
        base_price >= 0 AND 
        (emergency_price IS NULL OR emergency_price >= base_price) AND
        (insurance_price IS NULL OR insurance_price >= 0) AND
        tax_percentage >= 0
    ),
    CONSTRAINT check_effective_dates CHECK (
        effective_until IS NULL OR effective_until >= effective_from
    )
);

-- Indexes for service pricing
CREATE INDEX idx_pricing_code ON billing.service_pricing(service_code);
CREATE INDEX idx_pricing_category ON billing.service_pricing(service_category);
CREATE INDEX idx_pricing_active ON billing.service_pricing(is_active);

-- ============================================
-- PAYMENT PLANS
-- ============================================

CREATE TABLE billing.payment_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Bill Reference
    bill_id UUID REFERENCES billing.bills(id) NOT NULL,
    patient_id UUID REFERENCES clinical.patients(id) NOT NULL,
    
    -- Plan Details
    plan_name VARCHAR(100) NOT NULL,
    total_amount DECIMAL(12, 2) NOT NULL,
    down_payment DECIMAL(10, 2) DEFAULT 0 NOT NULL,
    remaining_amount DECIMAL(12, 2) NOT NULL,
    
    -- Installments
    number_of_installments INTEGER NOT NULL,
    installment_amount DECIMAL(10, 2) NOT NULL,
    installment_frequency VARCHAR(20) NOT NULL, -- weekly, biweekly, monthly
    
    -- Dates
    start_date DATE DEFAULT CURRENT_DATE NOT NULL,
    end_date DATE NOT NULL,
    next_due_date DATE NOT NULL,
    
    -- Status
    status VARCHAR(50) DEFAULT 'active' NOT NULL, -- active, completed, defaulted, cancelled
    installments_paid INTEGER DEFAULT 0 NOT NULL,
    amount_paid DECIMAL(12, 2) DEFAULT 0 NOT NULL,
    
    -- Late Fees
    late_fee_percentage DECIMAL(5, 2) DEFAULT 0,
    total_late_fees DECIMAL(10, 2) DEFAULT 0,
    
    -- Approval
    approved_by UUID REFERENCES core.users(id),
    approved_at TIMESTAMP,
    
    -- Notes
    notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_plan_amounts CHECK (
        total_amount > 0 AND 
        down_payment >= 0 AND 
        down_payment < total_amount AND
        remaining_amount > 0 AND
        installment_amount > 0 AND
        amount_paid >= 0 AND
        amount_paid <= total_amount
    ),
    CONSTRAINT check_plan_installments CHECK (number_of_installments > 0 AND installments_paid >= 0),
    CONSTRAINT check_plan_dates CHECK (end_date > start_date),
    CONSTRAINT check_plan_status CHECK (status IN ('active', 'completed', 'defaulted', 'cancelled'))
);

-- Indexes for payment plans
CREATE INDEX idx_payment_plans_bill ON billing.payment_plans(bill_id);
CREATE INDEX idx_payment_plans_patient ON billing.payment_plans(patient_id);
CREATE INDEX idx_payment_plans_status ON billing.payment_plans(status);
CREATE INDEX idx_payment_plans_due_date ON billing.payment_plans(next_due_date);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Function to generate bill number
CREATE OR REPLACE FUNCTION billing.generate_bill_number()
RETURNS VARCHAR AS $$
DECLARE
    year_part VARCHAR(4);
    count_part INTEGER;
    new_number VARCHAR(20);
BEGIN
    year_part := TO_CHAR(CURRENT_DATE, 'YYYY');
    
    SELECT COUNT(*) + 1 INTO count_part
    FROM billing.bills
    WHERE bill_number LIKE 'BILL-' || year_part || '-%';
    
    new_number := 'BILL-' || year_part || '-' || LPAD(count_part::TEXT, 6, '0');
    
    RETURN new_number;
END;
$$ LANGUAGE plpgsql;

-- Function to generate payment number
CREATE OR REPLACE FUNCTION billing.generate_payment_number()
RETURNS VARCHAR AS $$
DECLARE
    year_part VARCHAR(4);
    count_part INTEGER;
    new_number VARCHAR(20);
BEGIN
    year_part := TO_CHAR(CURRENT_DATE, 'YYYY');
    
    SELECT COUNT(*) + 1 INTO count_part
    FROM billing.payments
    WHERE payment_number LIKE 'PAY-' || year_part || '-%';
    
    new_number := 'PAY-' || year_part || '-' || LPAD(count_part::TEXT, 6, '0');
    
    RETURN new_number;
END;
$$ LANGUAGE plpgsql;

-- Function to generate claim number
CREATE OR REPLACE FUNCTION billing.generate_claim_number()
RETURNS VARCHAR AS $$
DECLARE
    year_part VARCHAR(4);
    count_part INTEGER;
    new_number VARCHAR(20);
BEGIN
    year_part := TO_CHAR(CURRENT_DATE, 'YYYY');
    
    SELECT COUNT(*) + 1 INTO count_part
    FROM billing.insurance_claims
    WHERE claim_number LIKE 'CLM-' || year_part || '-%';
    
    new_number := 'CLM-' || year_part || '-' || LPAD(count_part::TEXT, 6, '0');
    
    RETURN new_number;
END;
$$ LANGUAGE plpgsql;

-- Function to update bill paid amount after payment
CREATE OR REPLACE FUNCTION billing.update_bill_paid_amount()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'completed' THEN
        UPDATE billing.bills
        SET paid_amount = paid_amount + NEW.amount,
            status = CASE 
                WHEN paid_amount + NEW.amount >= total_amount THEN 'paid'::bill_status_enum
                WHEN paid_amount + NEW.amount > 0 THEN 'partial'::bill_status_enum
                ELSE status
            END,
            paid_date = CASE 
                WHEN paid_amount + NEW.amount >= total_amount THEN CURRENT_DATE
                ELSE paid_date
            END,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.bill_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-generate bill number
CREATE OR REPLACE FUNCTION billing.set_bill_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.bill_number IS NULL THEN
        NEW.bill_number := billing.generate_bill_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_bill_number
    BEFORE INSERT ON billing.bills
    FOR EACH ROW
    EXECUTE FUNCTION billing.set_bill_number();

-- Auto-generate payment number
CREATE OR REPLACE FUNCTION billing.set_payment_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.payment_number IS NULL THEN
        NEW.payment_number := billing.generate_payment_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_payment_number
    BEFORE INSERT ON billing.payments
    FOR EACH ROW
    EXECUTE FUNCTION billing.set_payment_number();

-- Auto-generate claim number
CREATE OR REPLACE FUNCTION billing.set_claim_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.claim_number IS NULL THEN
        NEW.claim_number := billing.generate_claim_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_claim_number
    BEFORE INSERT ON billing.insurance_claims
    FOR EACH ROW
    EXECUTE FUNCTION billing.set_claim_number();

-- Update bill after payment
CREATE TRIGGER trigger_update_bill_payment
    AFTER INSERT OR UPDATE ON billing.payments
    FOR EACH ROW
    EXECUTE FUNCTION billing.update_bill_paid_amount();

-- Updated_at triggers
CREATE TRIGGER update_bills_updated_at
    BEFORE UPDATE ON billing.bills
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_payments_updated_at
    BEFORE UPDATE ON billing.payments
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_claims_updated_at
    BEFORE UPDATE ON billing.insurance_claims
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_pricing_updated_at
    BEFORE UPDATE ON billing.service_pricing
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_payment_plans_updated_at
    BEFORE UPDATE ON billing.payment_plans
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

-- Audit triggers (CRITICAL for financial data)
CREATE TRIGGER audit_bills_changes
    AFTER INSERT OR UPDATE OR DELETE ON billing.bills
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_payments_changes
    AFTER INSERT OR UPDATE OR DELETE ON billing.payments
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_claims_changes
    AFTER INSERT OR UPDATE OR DELETE ON billing.insurance_claims
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON SCHEMA billing IS 'Billing, payments, and insurance management';
COMMENT ON TABLE billing.bills IS 'Patient bills - CRITICAL financial data';
COMMENT ON TABLE billing.payments IS 'Payment transactions - MUST be audited';
COMMENT ON TABLE billing.insurance_claims IS 'Insurance claims processing';
COMMENT ON TABLE billing.service_pricing IS 'Service pricing catalog';
COMMENT ON TABLE billing.payment_plans IS 'Patient payment plans and installments';

-- ============================================
-- SCHEMA VERSION
-- ============================================

INSERT INTO core.schema_versions (version, description) VALUES
    ('1.5.0', 'Billing and insurance management schema');

-- ============================================
-- END OF BILLING & INSURANCE SCHEMA
-- ============================================
