# API Specifications

## 1. API Architecture Overview

### 1.1 API Design Principles
```yaml
Design Standards:
  - RESTful architecture
  - JSON as primary data format
  - OAuth 2.0 / JWT authentication
  - Versioned endpoints (/api/v1/)
  - Consistent error handling
  - HATEOAS where applicable
  - Rate limiting per client
  - Request/Response validation
  - Comprehensive documentation
```

### 1.2 Base URL Structure
```
Production: https://api.hospital-system.com/api/v1
Staging: https://staging-api.hospital-system.com/api/v1
Development: http://localhost:3000/api/v1
```

### 1.3 Authentication Headers
```http
Authorization: Bearer <JWT_TOKEN>
X-API-Key: <API_KEY>
X-Request-ID: <UUID>
X-Client-Version: <VERSION>
```

## 2. Authentication & Authorization APIs

### 2.1 Authentication Endpoints

#### Login
```yaml
POST /auth/login
Description: Authenticate user and receive JWT token
Request:
  Content-Type: application/json
  Body:
    {
      "username": "string",
      "password": "string",
      "two_factor_code": "string (optional)"
    }
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "access_token": "jwt_token",
        "refresh_token": "refresh_token",
        "token_type": "Bearer",
        "expires_in": 3600,
        "user": {
          "id": "uuid",
          "username": "string",
          "email": "string",
          "user_type": "patient|doctor|staff|admin",
          "roles": ["role1", "role2"],
          "permissions": ["permission1", "permission2"]
        }
      }
    }
  401 Unauthorized:
    {
      "success": false,
      "error": {
        "code": "INVALID_CREDENTIALS",
        "message": "Invalid username or password"
      }
    }
```

#### Refresh Token
```yaml
POST /auth/refresh
Description: Refresh access token using refresh token
Request:
  Content-Type: application/json
  Body:
    {
      "refresh_token": "string"
    }
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "access_token": "new_jwt_token",
        "expires_in": 3600
      }
    }
```

#### Logout
```yaml
POST /auth/logout
Description: Invalidate current session
Request:
  Authorization: Bearer <token>
Response:
  200 OK:
    {
      "success": true,
      "message": "Logged out successfully"
    }
```

## 3. Patient Management APIs

### 3.1 Patient Registration

#### Create Patient
```yaml
POST /patients
Description: Register a new patient
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "first_name": "string",
      "middle_name": "string (optional)",
      "last_name": "string",
      "date_of_birth": "YYYY-MM-DD",
      "gender": "male|female|other",
      "blood_group": "A+|A-|B+|B-|AB+|AB-|O+|O-",
      "phone_primary": "string",
      "phone_secondary": "string (optional)",
      "email": "string",
      "address": {
        "line1": "string",
        "line2": "string (optional)",
        "city": "string",
        "state": "string",
        "country": "string",
        "postal_code": "string"
      },
      "emergency_contact": {
        "name": "string",
        "relationship": "string",
        "phone": "string"
      },
      "insurance": {
        "provider": "string",
        "policy_number": "string",
        "valid_until": "YYYY-MM-DD"
      }
    }
Response:
  201 Created:
    {
      "success": true,
      "data": {
        "patient_id": "uuid",
        "patient_number": "PAT-2024-00001",
        "created_at": "ISO8601_timestamp"
      }
    }
  400 Bad Request:
    {
      "success": false,
      "error": {
        "code": "VALIDATION_ERROR",
        "message": "Validation failed",
        "details": [
          {
            "field": "email",
            "message": "Invalid email format"
          }
        ]
      }
    }
```

#### Get Patient Details
```yaml
GET /patients/{patient_id}
Description: Retrieve patient information
Request:
  Authorization: Bearer <token>
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "id": "uuid",
        "patient_number": "PAT-2024-00001",
        "first_name": "string",
        "last_name": "string",
        "date_of_birth": "YYYY-MM-DD",
        "gender": "male|female|other",
        "blood_group": "A+",
        "contact": {
          "phone_primary": "string",
          "email": "string"
        },
        "address": {
          "line1": "string",
          "city": "string",
          "state": "string",
          "postal_code": "string"
        },
        "medical_summary": {
          "allergies": ["allergy1", "allergy2"],
          "chronic_conditions": ["condition1"],
          "current_medications": ["medication1"]
        },
        "insurance": {
          "provider": "string",
          "policy_number": "string",
          "valid_until": "YYYY-MM-DD",
          "verification_status": "verified"
        },
        "visit_history": {
          "last_visit": "YYYY-MM-DD",
          "total_visits": 15
        }
      }
    }
```

#### Update Patient
```yaml
PUT /patients/{patient_id}
Description: Update patient information
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "phone_primary": "string",
      "email": "string",
      "address": {
        "line1": "string",
        "city": "string"
      }
    }
Response:
  200 OK:
    {
      "success": true,
      "message": "Patient updated successfully"
    }
```

#### Search Patients
```yaml
GET /patients/search
Description: Search patients with filters
Request:
  Authorization: Bearer <token>
  Query Parameters:
    - q: "search term" (searches name, phone, email)
    - patient_number: "PAT-2024-00001"
    - phone: "1234567890"
    - email: "patient@email.com"
    - page: 1
    - limit: 20
    - sort: "created_at:desc"
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "patients": [
          {
            "id": "uuid",
            "patient_number": "PAT-2024-00001",
            "name": "John Doe",
            "phone": "1234567890",
            "last_visit": "2024-01-15"
          }
        ],
        "pagination": {
          "page": 1,
          "limit": 20,
          "total": 150,
          "pages": 8
        }
      }
    }
```

### 3.2 Medical Records

#### Get Medical History
```yaml
GET /patients/{patient_id}/medical-history
Description: Retrieve patient's medical history
Request:
  Authorization: Bearer <token>
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "medical_history": [
          {
            "id": "uuid",
            "condition_name": "Hypertension",
            "icd_code": "I10",
            "diagnosed_date": "2020-05-15",
            "is_chronic": true,
            "severity": "moderate",
            "notes": "Controlled with medication"
          }
        ],
        "allergies": [
          {
            "id": "uuid",
            "allergen_type": "drug",
            "allergen_name": "Penicillin",
            "reaction_type": "Anaphylaxis",
            "severity": "severe"
          }
        ],
        "family_history": [
          {
            "relationship": "father",
            "condition_name": "Diabetes Type 2",
            "age_at_diagnosis": 45
          }
        ],
        "immunizations": [
          {
            "vaccine_name": "COVID-19",
            "date_administered": "2023-12-01",
            "dose_number": 3
          }
        ]
      }
    }
```

## 4. Appointment Management APIs

### 4.1 Appointment Booking

#### Check Availability
```yaml
GET /appointments/availability
Description: Check available appointment slots
Request:
  Authorization: Bearer <token>
  Query Parameters:
    - doctor_id: "uuid"
    - department_id: "uuid"
    - date: "YYYY-MM-DD"
    - appointment_type: "consultation|follow-up"
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "available_slots": [
          {
            "slot_id": "uuid",
            "date": "2024-01-20",
            "time": "09:00",
            "duration_minutes": 30,
            "doctor": {
              "id": "uuid",
              "name": "Dr. Smith",
              "specialization": "Cardiology"
            }
          },
          {
            "slot_id": "uuid",
            "date": "2024-01-20",
            "time": "09:30",
            "duration_minutes": 30
          }
        ]
      }
    }
```

#### Book Appointment
```yaml
POST /appointments
Description: Book a new appointment
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "patient_id": "uuid",
      "doctor_id": "uuid",
      "appointment_date": "YYYY-MM-DD",
      "appointment_time": "HH:MM",
      "appointment_type": "consultation|follow-up|procedure",
      "reason_for_visit": "string",
      "symptoms": ["symptom1", "symptom2"],
      "priority": "normal|urgent"
    }
Response:
  201 Created:
    {
      "success": true,
      "data": {
        "appointment_id": "uuid",
        "appointment_number": "APT-2024-00001",
        "status": "scheduled",
        "confirmation_code": "ABC123",
        "appointment_details": {
          "date": "2024-01-20",
          "time": "09:00",
          "doctor": "Dr. Smith",
          "department": "Cardiology",
          "room": "Room 101"
        }
      }
    }
```

#### Cancel Appointment
```yaml
DELETE /appointments/{appointment_id}
Description: Cancel an appointment
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "cancellation_reason": "string"
    }
Response:
  200 OK:
    {
      "success": true,
      "message": "Appointment cancelled successfully"
    }
```

## 5. Clinical APIs

### 5.1 Consultation Management

#### Start Consultation
```yaml
POST /consultations
Description: Start a new consultation
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "appointment_id": "uuid",
      "patient_id": "uuid",
      "doctor_id": "uuid",
      "vitals": {
        "blood_pressure_systolic": 120,
        "blood_pressure_diastolic": 80,
        "pulse_rate": 72,
        "temperature": 98.6,
        "weight": 70,
        "height": 175
      }
    }
Response:
  201 Created:
    {
      "success": true,
      "data": {
        "consultation_id": "uuid",
        "status": "in_progress",
        "started_at": "ISO8601_timestamp"
      }
    }
```

#### Update Consultation
```yaml
PUT /consultations/{consultation_id}
Description: Update consultation details
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "chief_complaint": "string",
      "history_of_present_illness": "string",
      "physical_examination": "string",
      "provisional_diagnosis": "string",
      "treatment_plan": "string",
      "follow_up_required": true,
      "follow_up_date": "YYYY-MM-DD"
    }
Response:
  200 OK:
    {
      "success": true,
      "message": "Consultation updated successfully"
    }
```

### 5.2 Prescription Management

#### Create Prescription
```yaml
POST /prescriptions
Description: Create a new prescription
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "consultation_id": "uuid",
      "patient_id": "uuid",
      "doctor_id": "uuid",
      "medications": [
        {
          "medicine_id": "uuid",
          "dosage": "500mg",
          "frequency": "1-0-1",
          "duration_days": 7,
          "route": "oral",
          "food_relation": "after_food",
          "special_instructions": "Take with water"
        }
      ],
      "valid_until": "YYYY-MM-DD"
    }
Response:
  201 Created:
    {
      "success": true,
      "data": {
        "prescription_id": "uuid",
        "prescription_number": "RX-2024-00001",
        "status": "active",
        "created_at": "ISO8601_timestamp"
      }
    }
```

## 6. Laboratory APIs

### 6.1 Lab Test Management

#### Order Lab Tests
```yaml
POST /lab-orders
Description: Order laboratory tests
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "patient_id": "uuid",
      "doctor_id": "uuid",
      "consultation_id": "uuid",
      "tests": [
        {
          "test_id": "uuid",
          "priority": "routine|urgent|stat"
        }
      ],
      "clinical_notes": "string"
    }
Response:
  201 Created:
    {
      "success": true,
      "data": {
        "order_id": "uuid",
        "order_number": "LAB-2024-00001",
        "status": "ordered",
        "tests": [
          {
            "test_name": "Complete Blood Count",
            "sample_type": "blood",
            "sample_id": "SAMP-001"
          }
        ]
      }
    }
```

#### Get Lab Results
```yaml
GET /lab-orders/{order_id}/results
Description: Retrieve lab test results
Request:
  Authorization: Bearer <token>
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "order_id": "uuid",
        "order_number": "LAB-2024-00001",
        "status": "completed",
        "results": [
          {
            "test_name": "Hemoglobin",
            "result_value": "14.5",
            "unit": "g/dL",
            "reference_range": "13.5-17.5",
            "is_abnormal": false,
            "performed_at": "ISO8601_timestamp",
            "verified_by": "Lab Technician Name"
          }
        ],
        "report_url": "https://reports.hospital.com/lab/report.pdf"
      }
    }
```

## 7. Pharmacy APIs

### 7.1 Medicine Management

#### Search Medicines
```yaml
GET /medicines/search
Description: Search medicines in catalog
Request:
  Authorization: Bearer <token>
  Query Parameters:
    - q: "search term"
    - category: "antibiotics"
    - generic_name: "paracetamol"
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "medicines": [
          {
            "id": "uuid",
            "brand_name": "Tylenol",
            "generic_name": "Paracetamol",
            "strength": "500mg",
            "form": "tablet",
            "manufacturer": "Johnson & Johnson",
            "unit_price": 0.50,
            "in_stock": true
          }
        ]
      }
    }
```

#### Check Drug Interactions
```yaml
POST /medicines/check-interactions
Description: Check for drug interactions
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "patient_id": "uuid",
      "medicines": ["medicine_id_1", "medicine_id_2"]
    }
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "interactions": [
          {
            "drug1": "Warfarin",
            "drug2": "Aspirin",
            "severity": "major",
            "description": "Increased risk of bleeding",
            "recommendation": "Avoid combination or monitor closely"
          }
        ],
        "allergy_warnings": [
          {
            "medicine": "Penicillin",
            "allergy": "Penicillin allergy",
            "severity": "severe"
          }
        ]
      }
    }
```

## 8. Billing APIs

### 8.1 Bill Management

#### Generate Bill
```yaml
POST /bills
Description: Generate a new bill
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "patient_id": "uuid",
      "bill_type": "opd|ipd|emergency",
      "items": [
        {
          "item_type": "consultation",
          "item_name": "Doctor Consultation",
          "quantity": 1,
          "unit_price": 100.00
        },
        {
          "item_type": "lab_test",
          "item_name": "Blood Test",
          "quantity": 1,
          "unit_price": 50.00
        }
      ],
      "discount_percentage": 10,
      "insurance_claim_id": "uuid"
    }
Response:
  201 Created:
    {
      "success": true,
      "data": {
        "bill_id": "uuid",
        "bill_number": "BILL-2024-00001",
        "subtotal": 150.00,
        "discount_amount": 15.00,
        "tax_amount": 13.50,
        "total_amount": 148.50,
        "insurance_covered": 100.00,
        "patient_payable": 48.50
      }
    }
```

#### Process Payment
```yaml
POST /payments
Description: Process a payment
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "bill_id": "uuid",
      "amount": 48.50,
      "payment_method": "card",
      "card_details": {
        "card_number": "****1234",
        "card_holder": "John Doe",
        "transaction_id": "TXN123456"
      }
    }
Response:
  201 Created:
    {
      "success": true,
      "data": {
        "payment_id": "uuid",
        "payment_number": "PAY-2024-00001",
        "status": "completed",
        "receipt_url": "https://receipts.hospital.com/receipt.pdf"
      }
    }
```

## 9. AI/ML APIs

### 9.1 Diagnosis Assistance

#### Get Diagnosis Suggestions
```yaml
POST /ai/diagnosis-suggestions
Description: Get AI-powered diagnosis suggestions
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "symptoms": ["fever", "cough", "fatigue"],
      "duration_days": 3,
      "patient_age": 35,
      "patient_gender": "male",
      "medical_history": ["hypertension"],
      "vital_signs": {
        "temperature": 101.2,
        "pulse_rate": 90
      }
    }
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "suggestions": [
          {
            "condition": "Influenza",
            "icd_code": "J11.1",
            "confidence": 0.85,
            "reasoning": "Symptoms match typical flu presentation",
            "recommended_tests": ["Influenza rapid test", "CBC"],
            "treatment_options": [
              "Antiviral medication",
              "Symptomatic treatment"
            ]
          },
          {
            "condition": "COVID-19",
            "icd_code": "U07.1",
            "confidence": 0.75,
            "reasoning": "Common symptoms of COVID-19",
            "recommended_tests": ["RT-PCR", "Chest X-ray"]
          }
        ],
        "disclaimer": "AI suggestions are for assistance only. Clinical judgment required."
      }
    }
```

#### Predict Treatment Outcome
```yaml
POST /ai/treatment-outcome-prediction
Description: Predict treatment outcome using ML
Request:
  Authorization: Bearer <token>
  Content-Type: application/json
  Body:
    {
      "patient_id": "uuid",
      "diagnosis": "Type 2 Diabetes",
      "treatment_plan": {
        "medications": ["Metformin 500mg"],
        "lifestyle_changes": ["diet", "exercise"]
      },
      "patient_factors": {
        "age": 45,
        "bmi": 28,
        "compliance_history": "good"
      }
    }
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "predictions": {
          "success_probability": 0.78,
          "expected_improvement": {
            "hba1c_reduction": 1.2,
            "timeframe_weeks": 12
          },
          "risk_factors": [
            "BMI above normal range",
            "Age factor"
          ],
          "recommendations": [
            "Regular monitoring",
            "Dietary consultation"
          ]
        }
      }
    }
```

## 10. Analytics APIs

### 10.1 Dashboard Metrics

#### Get Hospital Dashboard
```yaml
GET /analytics/dashboard
Description: Get hospital dashboard metrics
Request:
  Authorization: Bearer <token>
  Query Parameters:
    - date_from: "YYYY-MM-DD"
    - date_to: "YYYY-MM-DD"
Response:
  200 OK:
    {
      "success": true,
      "data": {
        "summary": {
          "total_patients": 5420,
          "new_patients_today": 45,
          "appointments_today": 120,
          "bed_occupancy_rate": 0.85,
          "emergency_cases_today": 12
        },
        "department_stats": [
          {
            "department": "Cardiology",
            "patients_today": 25,
            "average_wait_time": 15
          }
        ],
        "financial": {
          "revenue_today": 45000,
          "pending_payments": 120000,
          "insurance_claims_pending": 85
        },
        "trends": {
          "patient_flow": [
            {"date": "2024-01-01", "count": 120},
            {"date": "2024-01-02", "count": 135}
          ]
        }
      }
    }
```

## 11. WebSocket Events

### 11.1 Real-time Updates
```javascript
// WebSocket connection
ws://api.hospital-system.com/ws

// Subscribe to events
{
  "action": "subscribe",
  "channels": ["emergency", "patient_updates", "lab_results"]
}

// Emergency alert event
{
  "event": "emergency_alert",
  "data": {
    "type": "code_blue",
    "location": "Room 302",
    "patient_id": "uuid",
    "timestamp": "ISO8601"
  }
}

// Patient vital update
{
  "event": "vital_update",
  "data": {
    "patient_id": "uuid",
    "vitals": {
      "pulse_rate": 120,
      "blood_pressure": "140/90",
      "alert": "high"
    }
  }
}

// Lab result ready
{
  "event": "lab_result_ready",
  "data": {
    "order_id": "uuid",
    "patient_id": "uuid",
    "critical_values": true
  }
}
```

## 12. Error Handling

### 12.1 Standard Error Response
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable error message",
    "details": {
      "field": "Additional error details"
    },
    "request_id": "uuid",
    "timestamp": "ISO8601"
  }
}
```

### 12.2 Error Codes
```yaml
Common Error Codes:
  - UNAUTHORIZED: Authentication required
  - FORBIDDEN: Insufficient permissions
  - NOT_FOUND: Resource not found
  - VALIDATION_ERROR: Input validation failed
  - DUPLICATE_ENTRY: Resource already exists
  - RATE_LIMIT_EXCEEDED: Too many requests
  - INTERNAL_ERROR: Server error
  - SERVICE_UNAVAILABLE: Service temporarily unavailable
```

## 13. Rate Limiting

### 13.1 Rate Limit Headers
```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1640995200
```

### 13.2 Rate Limit Tiers
```yaml
Tiers:
  Basic:
    requests_per_hour: 1000
    concurrent_requests: 10
  
  Premium:
    requests_per_hour: 10000
    concurrent_requests: 50
  
  Enterprise:
    requests_per_hour: unlimited
    concurrent_requests: 100
```

---

*This API specification provides comprehensive documentation for all endpoints in the Hospital Management System. Each endpoint is designed following REST principles with proper authentication, validation, and error handling.*
