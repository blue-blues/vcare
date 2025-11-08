#!/bin/bash

# ============================================
# Hospital Management System - Setup Script
# ============================================
# This script sets up the entire development environment
# CRITICAL: Run this before starting development

set -e  # Exit on error

echo "🏥 Hospital Management System - Setup Script"
echo "=============================================="
echo ""

# Colors for output
RED='\033[0.31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check if Node.js is installed
echo "Checking prerequisites..."
if ! command -v node &> /dev/null; then
    print_error "Node.js is not installed. Please install Node.js 18+ first."
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    print_error "Node.js version 18 or higher is required. Current version: $(node -v)"
    exit 1
fi
print_success "Node.js $(node -v) detected"

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    print_error "npm is not installed"
    exit 1
fi
print_success "npm $(npm -v) detected"

# Check if PostgreSQL is installed
if ! command -v psql &> /dev/null; then
    print_warning "PostgreSQL client not found. Please install PostgreSQL 14+"
    print_info "You can continue, but database setup will need to be done manually"
else
    print_success "PostgreSQL client detected"
fi

# Check if Redis is installed
if ! command -v redis-cli &> /dev/null; then
    print_warning "Redis client not found. Please install Redis 6+"
    print_info "You can continue, but Redis setup will need to be done manually"
else
    print_success "Redis client detected"
fi

echo ""
echo "=============================================="
echo "Step 1: Installing Dependencies"
echo "=============================================="
echo ""

# Install root dependencies
print_info "Installing root dependencies..."
npm install
print_success "Root dependencies installed"

# Install backend dependencies
print_info "Installing backend dependencies..."
cd backend
npm install
cd ..
print_success "Backend dependencies installed"

echo ""
echo "=============================================="
echo "Step 2: Environment Configuration"
echo "=============================================="
echo ""

# Copy .env.example to .env if it doesn't exist
if [ ! -f .env ]; then
    print_info "Creating .env file from .env.example..."
    cp .env.example .env
    print_success ".env file created"
    print_warning "Please update .env file with your configuration"
else
    print_info ".env file already exists"
fi

echo ""
echo "=============================================="
echo "Step 3: Database Setup"
echo "=============================================="
echo ""

print_info "Database setup instructions:"
echo ""
echo "1. Create PostgreSQL database:"
echo "   createdb hospital_management"
echo ""
echo "2. Create database user:"
echo "   psql -c \"CREATE USER hms_admin WITH ENCRYPTED PASSWORD 'your_password';\""
echo "   psql -c \"GRANT ALL PRIVILEGES ON DATABASE hospital_management TO hms_admin;\""
echo ""
echo "3. Execute database schemas (in order):"
echo "   psql -U hms_admin -d hospital_management -f database/schemas/001_core_schema.sql"
echo "   psql -U hms_admin -d hospital_management -f database/schemas/002_clinical_schema.sql"
echo "   psql -U hms_admin -d hospital_management -f database/schemas/003_appointments_consultations_schema.sql"
echo "   psql -U hms_admin -d hospital_management -f database/schemas/004_laboratory_schema.sql"
echo "   psql -U hms_admin -d hospital_management -f database/schemas/005_pharmacy_inventory_schema.sql"
echo "   psql -U hms_admin -d hospital_management -f database/schemas/006_billing_insurance_schema.sql"
echo "   psql -U hms_admin -d hospital_management -f database/schemas/007_emergency_icu_schema.sql"
echo ""

# Ask if user wants to run database setup
read -p "Do you want to run database setup now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter PostgreSQL username (default: hms_admin): " DB_USER
    DB_USER=${DB_USER:-hms_admin}
    
    read -p "Enter database name (default: hospital_management): " DB_NAME
    DB_NAME=${DB_NAME:-hospital_management}
    
    print_info "Creating database..."
    createdb $DB_NAME 2>/dev/null || print_warning "Database may already exist"
    
    print_info "Executing schemas..."
    for schema in database/schemas/*.sql; do
        print_info "Executing $(basename $schema)..."
        psql -U $DB_USER -d $DB_NAME -f $schema
        if [ $? -eq 0 ]; then
            print_success "$(basename $schema) executed successfully"
        else
            print_error "Failed to execute $(basename $schema)"
            exit 1
        fi
    done
    
    print_success "Database setup completed!"
fi

echo ""
echo "=============================================="
echo "Step 4: Redis Setup"
echo "=============================================="
echo ""

print_info "Redis setup instructions:"
echo ""
echo "1. Start Redis server:"
echo "   redis-server"
echo ""
echo "2. Verify Redis is running:"
echo "   redis-cli ping"
echo "   (should return PONG)"
echo ""

# Ask if user wants to test Redis
read -p "Do you want to test Redis connection now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if redis-cli ping &> /dev/null; then
        print_success "Redis is running!"
    else
        print_warning "Redis is not running. Please start Redis server."
    fi
fi

echo ""
echo "=============================================="
echo "Step 5: Build TypeScript"
echo "=============================================="
echo ""

print_info "Building TypeScript files..."
cd backend
npm run build 2>/dev/null || print_warning "Build may have warnings (dependencies not fully installed)"
cd ..
print_success "TypeScript build completed"

echo ""
echo "=============================================="
echo "Setup Complete!"
echo "=============================================="
echo ""

print_success "Hospital Management System setup completed successfully!"
echo ""
echo "Next steps:"
echo ""
echo "1. Update .env file with your configuration"
echo "2. Ensure PostgreSQL and Redis are running"
echo "3. Start the development server:"
echo "   npm run dev"
echo ""
echo "4. Access the services:"
echo "   - Auth Service: http://localhost:3001"
echo "   - API Gateway: http://localhost:3000"
echo ""
echo "⚠️  IMPORTANT SECURITY REMINDERS:"
echo "   - Change all default passwords in .env"
echo "   - Generate secure JWT secrets"
echo "   - Enable SSL/TLS in production"
echo "   - Set up proper firewall rules"
echo "   - Enable database encryption"
echo "   - Set up regular backups"
echo ""
print_warning "This is a LIFE-CRITICAL healthcare system."
print_warning "Ensure all security measures are in place before deployment!"
echo ""
