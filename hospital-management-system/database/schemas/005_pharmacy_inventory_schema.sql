-- ============================================
-- HOSPITAL MANAGEMENT SYSTEM - PHARMACY & INVENTORY SCHEMA
-- ============================================
-- ⚠️ CRITICAL: Medication errors can be fatal
-- Strict validation and tracking required

SET search_path TO inventory, clinical, core, audit, public;

-- Create inventory schema if not exists
CREATE SCHEMA IF NOT EXISTS inventory;

-- ============================================
-- CUSTOM TYPES
-- ============================================

CREATE TYPE medicine_form_enum AS ENUM (
    'tablet',
    'capsule',
    'syrup',
    'suspension',
    'injection',
    'cream',
    'ointment',
    'gel',
    'drops',
    'inhaler',
    'patch',
    'suppository',
    'powder',
    'solution',
    'other'
);

CREATE TYPE storage_condition_enum AS ENUM (
    'room_temperature',
    'refrigerated',
    'frozen',
    'controlled_room_temperature',
    'protect_from_light',
    'protect_from_moisture'
);

CREATE TYPE transaction_type_enum AS ENUM (
    'purchase',
    'sale',
    'return',
    'adjustment',
    'expired',
    'damaged',
    'transfer',
    'donation'
);

-- ============================================
-- MEDICINES CATALOG
-- ============================================

CREATE TABLE inventory.medicines (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    medicine_code VARCHAR(20) UNIQUE NOT NULL,
    barcode VARCHAR(50) UNIQUE,
    
    -- Names
    brand_name VARCHAR(255) NOT NULL,
    generic_name VARCHAR(255) NOT NULL,
    scientific_name VARCHAR(255),
    
    -- Manufacturer
    manufacturer VARCHAR(255) NOT NULL,
    manufacturer_code VARCHAR(50),
    country_of_origin VARCHAR(100),
    
    -- Classification
    category VARCHAR(100) NOT NULL,
    drug_class VARCHAR(100),
    therapeutic_class VARCHAR(100),
    
    -- Controlled Substance
    is_controlled_substance BOOLEAN DEFAULT false NOT NULL,
    schedule_type VARCHAR(10), -- Schedule II, III, IV, V (DEA classification)
    requires_prescription BOOLEAN DEFAULT true NOT NULL,
    
    -- Formulation
    form medicine_form_enum NOT NULL,
    strength VARCHAR(100) NOT NULL,
    unit_of_measure VARCHAR(50) NOT NULL,
    
    -- Packaging
    pack_size INTEGER NOT NULL,
    pack_unit VARCHAR(50),
    
    -- Storage
    storage_conditions storage_condition_enum[] NOT NULL,
    storage_temperature_min DECIMAL(5, 2),
    storage_temperature_max DECIMAL(5, 2),
    special_storage_instructions TEXT,
    
    -- Pricing
    unit_price DECIMAL(10, 2) NOT NULL,
    mrp DECIMAL(10, 2), -- Maximum Retail Price
    
    -- Regulatory
    fda_approved BOOLEAN DEFAULT false,
    approval_number VARCHAR(100),
    ndc_code VARCHAR(20), -- National Drug Code
    
    -- Interactions and Warnings
    drug_interactions TEXT[],
    contraindications TEXT[],
    side_effects TEXT[],
    warnings TEXT[],
    pregnancy_category VARCHAR(10),
    
    -- Usage
    indications TEXT,
    dosage_instructions TEXT,
    
    -- Status
    is_active BOOLEAN DEFAULT true NOT NULL,
    is_available BOOLEAN DEFAULT true NOT NULL,
    discontinuation_date DATE,
    discontinuation_reason TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_unit_price CHECK (unit_price >= 0),
    CONSTRAINT check_mrp CHECK (mrp IS NULL OR mrp >= unit_price),
    CONSTRAINT check_pack_size CHECK (pack_size > 0),
    CONSTRAINT check_storage_temp CHECK (
        (storage_temperature_min IS NULL AND storage_temperature_max IS NULL) OR
        (storage_temperature_min IS NOT NULL AND storage_temperature_max IS NOT NULL AND 
         storage_temperature_max > storage_temperature_min)
    )
);

-- Indexes for medicines
CREATE INDEX idx_medicines_code ON inventory.medicines(medicine_code);
CREATE INDEX idx_medicines_barcode ON inventory.medicines(barcode);
CREATE INDEX idx_medicines_brand ON inventory.medicines(brand_name);
CREATE INDEX idx_medicines_generic ON inventory.medicines(generic_name);
CREATE INDEX idx_medicines_category ON inventory.medicines(category);
CREATE INDEX idx_medicines_active ON inventory.medicines(is_active);
CREATE INDEX idx_medicines_controlled ON inventory.medicines(is_controlled_substance);

-- Full-text search on medicine names
CREATE INDEX idx_medicines_name_fts ON inventory.medicines USING gin(
    to_tsvector('english', 
        brand_name || ' ' || 
        generic_name || ' ' || 
        COALESCE(scientific_name, '')
    )
);

-- ============================================
-- PHARMACY INVENTORY
-- ============================================

CREATE TABLE inventory.pharmacy_inventory (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    medicine_id UUID REFERENCES inventory.medicines(id) NOT NULL,
    
    -- Batch Information
    batch_number VARCHAR(50) NOT NULL,
    lot_number VARCHAR(50),
    
    -- Stock Information
    quantity_in_stock INTEGER NOT NULL,
    unit_of_measure VARCHAR(50) NOT NULL,
    
    -- Dates
    manufacture_date DATE NOT NULL,
    expiry_date DATE NOT NULL,
    received_date DATE DEFAULT CURRENT_DATE NOT NULL,
    
    -- Thresholds
    reorder_level INTEGER NOT NULL,
    max_stock_level INTEGER NOT NULL,
    min_stock_level INTEGER DEFAULT 0 NOT NULL,
    
    -- Supplier Information
    supplier_id UUID REFERENCES inventory.suppliers(id),
    purchase_order_number VARCHAR(50),
    purchase_price DECIMAL(10, 2) NOT NULL,
    selling_price DECIMAL(10, 2) NOT NULL,
    
    -- Storage
    storage_location VARCHAR(100) NOT NULL,
    rack_number VARCHAR(50),
    shelf_number VARCHAR(50),
    bin_number VARCHAR(50),
    
    -- Quality
    is_quarantined BOOLEAN DEFAULT false NOT NULL,
    quarantine_reason TEXT,
    quarantine_date DATE,
    quality_check_passed BOOLEAN,
    quality_check_date DATE,
    quality_checked_by UUID REFERENCES core.users(id),
    
    -- Status
    is_active BOOLEAN DEFAULT true NOT NULL,
    is_expired BOOLEAN GENERATED ALWAYS AS (expiry_date < CURRENT_DATE) STORED,
    days_to_expiry INTEGER GENERATED ALWAYS AS (expiry_date - CURRENT_DATE) STORED,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_quantity CHECK (quantity_in_stock >= 0),
    CONSTRAINT check_dates CHECK (expiry_date > manufacture_date),
    CONSTRAINT check_prices CHECK (purchase_price >= 0 AND selling_price >= purchase_price),
    CONSTRAINT check_stock_levels CHECK (
        min_stock_level >= 0 AND 
        reorder_level >= min_stock_level AND 
        max_stock_level >= reorder_level
    ),
    CONSTRAINT unique_medicine_batch UNIQUE(medicine_id, batch_number)
);

-- Indexes for pharmacy inventory
CREATE INDEX idx_inventory_medicine ON inventory.pharmacy_inventory(medicine_id);
CREATE INDEX idx_inventory_batch ON inventory.pharmacy_inventory(batch_number);
CREATE INDEX idx_inventory_expiry ON inventory.pharmacy_inventory(expiry_date);
CREATE INDEX idx_inventory_quantity ON inventory.pharmacy_inventory(quantity_in_stock);
CREATE INDEX idx_inventory_active ON inventory.pharmacy_inventory(is_active);
CREATE INDEX idx_inventory_expired ON inventory.pharmacy_inventory(is_expired);
CREATE INDEX idx_inventory_quarantined ON inventory.pharmacy_inventory(is_quarantined);

-- Index for low stock alerts
CREATE INDEX idx_inventory_low_stock ON inventory.pharmacy_inventory(medicine_id, quantity_in_stock)
WHERE quantity_in_stock <= reorder_level;

-- ============================================
-- SUPPLIERS
-- ============================================

CREATE TABLE inventory.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    supplier_code VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    
    -- Contact Person
    contact_person VARCHAR(255),
    designation VARCHAR(100),
    
    -- Contact Information
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(255),
    fax VARCHAR(20),
    website VARCHAR(255),
    
    -- Address
    address_line1 VARCHAR(255) NOT NULL,
    address_line2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    country VARCHAR(100) DEFAULT 'USA' NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    
    -- Business Information
    tax_id VARCHAR(50),
    license_number VARCHAR(50),
    gst_number VARCHAR(50),
    drug_license_number VARCHAR(50),
    
    -- Banking
    bank_name VARCHAR(255),
    account_number VARCHAR(50),
    ifsc_code VARCHAR(20),
    
    -- Terms
    payment_terms VARCHAR(100),
    credit_period_days INTEGER DEFAULT 0,
    delivery_terms VARCHAR(100),
    minimum_order_value DECIMAL(10, 2),
    
    -- Performance
    rating DECIMAL(3, 2) DEFAULT 0.00,
    total_orders INTEGER DEFAULT 0,
    total_purchase_value DECIMAL(15, 2) DEFAULT 0,
    on_time_delivery_percentage DECIMAL(5, 2),
    
    -- Status
    is_active BOOLEAN DEFAULT true NOT NULL,
    is_verified BOOLEAN DEFAULT false,
    verification_date DATE,
    
    -- Notes
    notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_rating CHECK (rating >= 0 AND rating <= 5),
    CONSTRAINT check_credit_period CHECK (credit_period_days >= 0),
    CONSTRAINT check_min_order CHECK (minimum_order_value IS NULL OR minimum_order_value >= 0)
);

-- Indexes for suppliers
CREATE INDEX idx_suppliers_code ON inventory.suppliers(supplier_code);
CREATE INDEX idx_suppliers_name ON inventory.suppliers(name);
CREATE INDEX idx_suppliers_active ON inventory.suppliers(is_active);

-- ============================================
-- PURCHASE ORDERS
-- ============================================

CREATE TABLE inventory.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Identification
    po_number VARCHAR(20) UNIQUE NOT NULL,
    
    -- Supplier
    supplier_id UUID REFERENCES inventory.suppliers(id) NOT NULL,
    
    -- Order Details
    order_date DATE DEFAULT CURRENT_DATE NOT NULL,
    expected_delivery_date DATE NOT NULL,
    actual_delivery_date DATE,
    
    -- Status
    status VARCHAR(50) DEFAULT 'draft' NOT NULL, -- draft, submitted, approved, received, cancelled
    
    -- Amounts
    subtotal DECIMAL(12, 2) NOT NULL,
    tax_amount DECIMAL(10, 2) DEFAULT 0,
    discount_amount DECIMAL(10, 2) DEFAULT 0,
    shipping_charges DECIMAL(10, 2) DEFAULT 0,
    total_amount DECIMAL(12, 2) NOT NULL,
    
    -- Payment
    payment_terms VARCHAR(100),
    payment_status VARCHAR(50) DEFAULT 'pending', -- pending, partial, paid
    paid_amount DECIMAL(12, 2) DEFAULT 0,
    
    -- Approval
    approved_by UUID REFERENCES core.users(id),
    approved_at TIMESTAMP,
    
    -- Receiving
    received_by UUID REFERENCES core.users(id),
    received_at TIMESTAMP,
    
    -- Notes
    notes TEXT,
    terms_and_conditions TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by UUID REFERENCES core.users(id),
    
    CONSTRAINT check_po_amounts CHECK (
        subtotal >= 0 AND 
        tax_amount >= 0 AND 
        discount_amount >= 0 AND 
        shipping_charges >= 0 AND
        total_amount >= 0 AND
        paid_amount >= 0 AND
        paid_amount <= total_amount
    ),
    CONSTRAINT check_po_dates CHECK (expected_delivery_date >= order_date),
    CONSTRAINT check_po_status CHECK (status IN ('draft', 'submitted', 'approved', 'received', 'cancelled'))
);

-- Indexes for purchase orders
CREATE INDEX idx_po_number ON inventory.purchase_orders(po_number);
CREATE INDEX idx_po_supplier ON inventory.purchase_orders(supplier_id);
CREATE INDEX idx_po_status ON inventory.purchase_orders(status);
CREATE INDEX idx_po_date ON inventory.purchase_orders(order_date);

-- ============================================
-- PURCHASE ORDER ITEMS
-- ============================================

CREATE TABLE inventory.purchase_order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_id UUID REFERENCES inventory.purchase_orders(id) ON DELETE CASCADE NOT NULL,
    medicine_id UUID REFERENCES inventory.medicines(id) NOT NULL,
    
    -- Quantity
    quantity_ordered INTEGER NOT NULL,
    quantity_received INTEGER DEFAULT 0 NOT NULL,
    unit_of_measure VARCHAR(50) NOT NULL,
    
    -- Pricing
    unit_price DECIMAL(10, 2) NOT NULL,
    discount_percentage DECIMAL(5, 2) DEFAULT 0,
    tax_percentage DECIMAL(5, 2) DEFAULT 0,
    total_price DECIMAL(12, 2) NOT NULL,
    
    -- Batch Information (filled on receipt)
    batch_number VARCHAR(50),
    manufacture_date DATE,
    expiry_date DATE,
    
    -- Status
    is_received BOOLEAN DEFAULT false NOT NULL,
    received_date DATE,
    
    -- Notes
    notes TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_poi_quantity CHECK (quantity_ordered > 0 AND quantity_received >= 0 AND quantity_received <= quantity_ordered),
    CONSTRAINT check_poi_prices CHECK (unit_price >= 0 AND total_price >= 0),
    CONSTRAINT check_poi_percentages CHECK (discount_percentage >= 0 AND discount_percentage <= 100 AND tax_percentage >= 0)
);

-- Indexes for purchase order items
CREATE INDEX idx_poi_po ON inventory.purchase_order_items(po_id);
CREATE INDEX idx_poi_medicine ON inventory.purchase_order_items(medicine_id);

-- ============================================
-- PHARMACY TRANSACTIONS
-- ============================================

CREATE TABLE inventory.pharmacy_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Transaction Details
    transaction_type transaction_type_enum NOT NULL,
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    -- Medicine and Batch
    medicine_id UUID REFERENCES inventory.medicines(id) NOT NULL,
    inventory_id UUID REFERENCES inventory.pharmacy_inventory(id),
    batch_number VARCHAR(50) NOT NULL,
    
    -- Quantity
    quantity INTEGER NOT NULL,
    unit_of_measure VARCHAR(50) NOT NULL,
    
    -- Pricing
    unit_price DECIMAL(10, 2) NOT NULL,
    total_amount DECIMAL(12, 2) NOT NULL,
    
    -- References
    reference_type VARCHAR(50), -- prescription, purchase_order, adjustment, etc.
    reference_id UUID,
    reference_number VARCHAR(50),
    
    -- Parties
    patient_id UUID REFERENCES clinical.patients(id),
    supplier_id UUID REFERENCES inventory.suppliers(id),
    
    -- Staff
    performed_by UUID REFERENCES core.users(id) NOT NULL,
    
    -- Notes
    notes TEXT,
    reason TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_transaction_quantity CHECK (quantity != 0),
    CONSTRAINT check_transaction_prices CHECK (unit_price >= 0 AND total_amount >= 0)
);

-- Indexes for pharmacy transactions
CREATE INDEX idx_transactions_type ON inventory.pharmacy_transactions(transaction_type);
CREATE INDEX idx_transactions_date ON inventory.pharmacy_transactions(transaction_date);
CREATE INDEX idx_transactions_medicine ON inventory.pharmacy_transactions(medicine_id);
CREATE INDEX idx_transactions_patient ON inventory.pharmacy_transactions(patient_id);
CREATE INDEX idx_transactions_reference ON inventory.pharmacy_transactions(reference_type, reference_id);

-- ============================================
-- STOCK ALERTS
-- ============================================

CREATE TABLE inventory.stock_alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Alert Details
    alert_type VARCHAR(50) NOT NULL, -- low_stock, out_of_stock, expiring_soon, expired
    severity VARCHAR(20) NOT NULL, -- low, medium, high, critical
    
    -- Medicine
    medicine_id UUID REFERENCES inventory.medicines(id) NOT NULL,
    inventory_id UUID REFERENCES inventory.pharmacy_inventory(id),
    
    -- Alert Information
    current_quantity INTEGER,
    reorder_level INTEGER,
    expiry_date DATE,
    days_to_expiry INTEGER,
    
    -- Status
    is_resolved BOOLEAN DEFAULT false NOT NULL,
    resolved_at TIMESTAMP,
    resolved_by UUID REFERENCES core.users(id),
    resolution_notes TEXT,
    
    -- Notifications
    notification_sent BOOLEAN DEFAULT false,
    notification_sent_at TIMESTAMP,
    notified_users UUID[],
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    CONSTRAINT check_alert_type CHECK (alert_type IN ('low_stock', 'out_of_stock', 'expiring_soon', 'expired', 'quarantined')),
    CONSTRAINT check_severity CHECK (severity IN ('low', 'medium', 'high', 'critical'))
);

-- Indexes for stock alerts
CREATE INDEX idx_alerts_type ON inventory.stock_alerts(alert_type);
CREATE INDEX idx_alerts_severity ON inventory.stock_alerts(severity);
CREATE INDEX idx_alerts_medicine ON inventory.stock_alerts(medicine_id);
CREATE INDEX idx_alerts_resolved ON inventory.stock_alerts(is_resolved);
CREATE INDEX idx_alerts_created ON inventory.stock_alerts(created_at);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Function to generate PO number
CREATE OR REPLACE FUNCTION inventory.generate_po_number()
RETURNS VARCHAR AS $$
DECLARE
    year_part VARCHAR(4);
    count_part INTEGER;
    new_number VARCHAR(20);
BEGIN
    year_part := TO_CHAR(CURRENT_DATE, 'YYYY');
    
    SELECT COUNT(*) + 1 INTO count_part
    FROM inventory.purchase_orders
    WHERE po_number LIKE 'PO-' || year_part || '-%';
    
    new_number := 'PO-' || year_part || '-' || LPAD(count_part::TEXT, 6, '0');
    
    RETURN new_number;
END;
$$ LANGUAGE plpgsql;

-- Function to check drug interactions
CREATE OR REPLACE FUNCTION inventory.check_drug_interactions(
    p_medicine_ids UUID[]
)
RETURNS TABLE(medicine1_id UUID, medicine2_id UUID, interaction_description TEXT) AS $$
BEGIN
    -- This is a simplified version. In production, this would check against
    -- a comprehensive drug interaction database
    RETURN QUERY
    SELECT 
        m1.id,
        m2.id,
        'Potential interaction detected'::TEXT
    FROM inventory.medicines m1
    CROSS JOIN inventory.medicines m2
    WHERE m1.id = ANY(p_medicine_ids)
    AND m2.id = ANY(p_medicine_ids)
    AND m1.id < m2.id
    AND m1.drug_interactions && ARRAY[m2.generic_name];
END;
$$ LANGUAGE plpgsql;

-- Function to update stock after transaction
CREATE OR REPLACE FUNCTION inventory.update_stock_after_transaction()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.transaction_type IN ('sale', 'expired', 'damaged') THEN
        -- Decrease stock
        UPDATE inventory.pharmacy_inventory
        SET quantity_in_stock = quantity_in_stock - NEW.quantity,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.inventory_id;
    ELSIF NEW.transaction_type IN ('purchase', 'return') THEN
        -- Increase stock
        UPDATE inventory.pharmacy_inventory
        SET quantity_in_stock = quantity_in_stock + NEW.quantity,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.inventory_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-generate PO number
CREATE OR REPLACE FUNCTION inventory.set_po_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.po_number IS NULL THEN
        NEW.po_number := inventory.generate_po_number();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_po_number
    BEFORE INSERT ON inventory.purchase_orders
    FOR EACH ROW
    EXECUTE FUNCTION inventory.set_po_number();

-- Update stock after transaction
CREATE TRIGGER trigger_update_stock
    AFTER INSERT ON inventory.pharmacy_transactions
    FOR EACH ROW
    EXECUTE FUNCTION inventory.update_stock_after_transaction();

-- Updated_at triggers
CREATE TRIGGER update_medicines_updated_at
    BEFORE UPDATE ON inventory.medicines
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_inventory_updated_at
    BEFORE UPDATE ON inventory.pharmacy_inventory
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_suppliers_updated_at
    BEFORE UPDATE ON inventory.suppliers
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

CREATE TRIGGER update_po_updated_at
    BEFORE UPDATE ON inventory.purchase_orders
    FOR EACH ROW
    EXECUTE FUNCTION core.update_updated_at_column();

-- Audit triggers (CRITICAL for controlled substances)
CREATE TRIGGER audit_medicines_changes
    AFTER INSERT OR UPDATE OR DELETE ON inventory.medicines
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_inventory_changes
    AFTER INSERT OR UPDATE OR DELETE ON inventory.pharmacy_inventory
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_transactions_changes
    AFTER INSERT OR UPDATE OR DELETE ON inventory.pharmacy_transactions
    FOR EACH ROW
    EXECUTE FUNCTION audit.log_changes();

-- ============================================
-- COMMENTS
-- ============================================

COMMENT ON SCHEMA inventory IS 'Pharmacy and inventory management';
COMMENT ON TABLE inventory.medicines IS 'Medicine catalog - includes controlled substances';
COMMENT ON TABLE inventory.pharmacy_inventory IS 'Current stock levels - CRITICAL for availability';
COMMENT ON TABLE inventory.pharmacy_transactions IS 'All stock movements - MUST be audited';
COMMENT ON TABLE inventory.stock_alerts IS 'Automated alerts for stock management';
COMMENT ON FUNCTION inventory.check_drug_interactions IS 'Checks for potential drug interactions - CRITICAL for safety';

-- ============================================
-- SCHEMA VERSION
-- ============================================

INSERT INTO core.schema_versions (version, description) VALUES
    ('1.4.0', 'Pharmacy and inventory management schema');

-- ============================================
-- END OF PHARMACY & INVENTORY SCHEMA
-- ============================================
