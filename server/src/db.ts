import "dotenv/config";
import {Pool} from "pg";

// Stop at startup if .env file (DATABASE_URL) is missing
if (!process.env.DATABASE_URL) {
    console.error("Error: DATABASE_URL environment variable is not set.");
    process.exit(1);
}

// Shared PostgreSQL connection pool used by every query on the server
export const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

pool.on("error", (err) => console.error("Postgres pool error:", err));
