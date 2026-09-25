import "dotenv/config";
import {Pool} from "pg";

// Create a PostgreSQL connection pool using the connection string from environment variables
// The connection string should be in the format: postgres://username:password@host:port/database
export const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
})