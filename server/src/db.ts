import "dotenv/config";
import {Pool} from "pg";

// Stop at startup with a clear message if the .env file (DATABASE_URL) is missing.
if (!process.env.DATABASE_URL) {
    console.error("Error: DATABASE_URL environment variable is not set.");
    process.exit(1);
}

// Shared PostgreSQL connection pool used by every query on the server.
export const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

// Logs dropped idle connections (e.g. Postgres restarting) instead of letting them crash Node.
pool.on("error", (err) => console.error("Postgres pool error:", err));
