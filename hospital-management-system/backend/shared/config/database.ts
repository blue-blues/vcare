/**
 * Database Configuration and Connection Pool
 * CRITICAL: Handles all database connections with proper error handling
 */

import { Pool, PoolConfig, QueryResult } from 'pg';
import { createClient } from 'redis';

// PostgreSQL Connection Pool
const poolConfig: PoolConfig = {
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME || 'hospital_management',
  user: process.env.DB_USER || 'hms_admin',
  password: process.env.DB_PASSWORD,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
  
  // Connection pool settings
  min: parseInt(process.env.DB_POOL_MIN || '2'),
  max: parseInt(process.env.DB_POOL_MAX || '10'),
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: parseInt(process.env.DB_CONNECTION_TIMEOUT || '30000'),
  
  // Statement timeout (30 seconds)
  statement_timeout: 30000,
  
  // Query timeout (30 seconds)
  query_timeout: 30000,
};

// Create PostgreSQL pool
export const pool = new Pool(poolConfig);

// Pool error handler
pool.on('error', (err: Error) => {
  console.error('Unexpected error on idle PostgreSQL client', err);
  process.exit(-1);
});

// Pool connection handler
pool.on('connect', () => {
  console.log('New PostgreSQL client connected to pool');
});

// Pool removal handler
pool.on('remove', () => {
  console.log('PostgreSQL client removed from pool');
});

/**
 * Execute a query with automatic error handling and logging
 */
export async function query<T = any>(
  text: string,
  params?: any[]
): Promise<QueryResult<T>> {
  const start = Date.now();
  
  try {
    const result = await pool.query<T>(text, params);
    const duration = Date.now() - start;
    
    // Log slow queries (> 1 second)
    if (duration > 1000) {
      console.warn('Slow query detected:', {
        text,
        duration: `${duration}ms`,
        rows: result.rowCount,
      });
    }
    
    return result;
  } catch (error) {
    console.error('Database query error:', {
      text,
      params,
      error: error instanceof Error ? error.message : 'Unknown error',
    });
    throw error;
  }
}

/**
 * Execute a transaction with automatic rollback on error
 */
export async function transaction<T>(
  callback: (client: any) => Promise<T>
): Promise<T> {
  const client = await pool.connect();
  
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Transaction error:', error);
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Set application context for audit logging
 */
export async function setAuditContext(
  client: any,
  userId: string,
  sessionId: string
): Promise<void> {
  await client.query(`SET LOCAL app.current_user_id = '${userId}'`);
  await client.query(`SET LOCAL app.session_id = '${sessionId}'`);
}

/**
 * Test database connection
 */
export async function testConnection(): Promise<boolean> {
  try {
    const result = await query('SELECT NOW() as current_time');
    console.log('Database connection successful:', result.rows[0].current_time);
    return true;
  } catch (error) {
    console.error('Database connection failed:', error);
    return false;
  }
}

/**
 * Close all database connections
 */
export async function closePool(): Promise<void> {
  await pool.end();
  console.log('PostgreSQL pool closed');
}

// Redis Configuration
const redisConfig = {
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  password: process.env.REDIS_PASSWORD || undefined,
  db: parseInt(process.env.REDIS_DB || '0'),
};

// Create Redis client
export const redisClient = createClient({
  socket: {
    host: redisConfig.host,
    port: redisConfig.port,
  },
  password: redisConfig.password,
  database: redisConfig.db,
});

// Redis error handler
redisClient.on('error', (err: Error) => {
  console.error('Redis Client Error:', err);
});

// Redis connection handler
redisClient.on('connect', () => {
  console.log('Redis client connected');
});

// Connect Redis
export async function connectRedis(): Promise<void> {
  try {
    await redisClient.connect();
    console.log('Redis connection successful');
  } catch (error) {
    console.error('Redis connection failed:', error);
    throw error;
  }
}

/**
 * Cache helper functions
 */
export const cache = {
  /**
   * Get value from cache
   */
  async get<T>(key: string): Promise<T | null> {
    try {
      const value = await redisClient.get(key);
      return value ? JSON.parse(value) : null;
    } catch (error) {
      console.error('Cache get error:', error);
      return null;
    }
  },

  /**
   * Set value in cache with TTL
   */
  async set(key: string, value: any, ttl?: number): Promise<void> {
    try {
      const serialized = JSON.stringify(value);
      if (ttl) {
        await redisClient.setEx(key, ttl, serialized);
      } else {
        await redisClient.set(key, serialized);
      }
    } catch (error) {
      console.error('Cache set error:', error);
    }
  },

  /**
   * Delete value from cache
   */
  async del(key: string): Promise<void> {
    try {
      await redisClient.del(key);
    } catch (error) {
      console.error('Cache delete error:', error);
    }
  },

  /**
   * Check if key exists
   */
  async exists(key: string): Promise<boolean> {
    try {
      const result = await redisClient.exists(key);
      return result === 1;
    } catch (error) {
      console.error('Cache exists error:', error);
      return false;
    }
  },

  /**
   * Set expiry on existing key
   */
  async expire(key: string, seconds: number): Promise<void> {
    try {
      await redisClient.expire(key, seconds);
    } catch (error) {
      console.error('Cache expire error:', error);
    }
  },
};

/**
 * Initialize all database connections
 */
export async function initializeDatabase(): Promise<void> {
  console.log('Initializing database connections...');
  
  // Test PostgreSQL connection
  const pgConnected = await testConnection();
  if (!pgConnected) {
    throw new Error('Failed to connect to PostgreSQL');
  }
  
  // Connect to Redis
  await connectRedis();
  
  console.log('All database connections initialized successfully');
}

/**
 * Graceful shutdown
 */
export async function shutdownDatabase(): Promise<void> {
  console.log('Shutting down database connections...');
  
  await closePool();
  await redisClient.quit();
  
  console.log('All database connections closed');
}

// Handle process termination
process.on('SIGINT', async () => {
  await shutdownDatabase();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  await shutdownDatabase();
  process.exit(0);
});
