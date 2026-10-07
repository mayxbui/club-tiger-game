import { randomBytes, createHash } from "crypto";
import { pool } from "./db.js";

// Session expiration times in milliseconds
const SHORT_SESSION_MS = 24 * 60 * 60 * 1000; // 1 day
const REMEMBER_ME_SESSION_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

// Hash a token using SHA-256
export function hashToken(token: string): string {
    return createHash("sha256").update(token).digest("hex");
}

// Creates a random session token, stores its hash with an expiry time, and returns the plain token for the client.
export async function createSession(userId: number, rememberMe: boolean): Promise<string> {
    const token = randomBytes(32).toString("hex");
    const expiresAt = new Date(Date.now() + (rememberMe ? REMEMBER_ME_SESSION_MS : SHORT_SESSION_MS));

    // Insert the session into the database with the specified expiration time
    await pool.query(
        `INSERT INTO sessions (user_id, token_hashed, expires_at)
         VALUES ($1, $2, $3)`,
        [userId, hashToken(token), expiresAt]
    );

    return token;
}

// Returns the user ID for a valid, unexpired token, or null if the token is missing, wrong, or expired.
export async function validateSession(token: string): Promise<number | null> {
    if (typeof token !== "string") {
        return null; // Return null for invalid token types
    }
    const result = await pool.query(
        `UPDATE sessions
            SET expires_at = LEAST(now() + interval '1 day', created_at + interval '30 days')
            WHERE token_hashed = $1 AND expires_at > now()
            RETURNING user_id`,
        [hashToken(token)]
    );
    return result.rows[0]?.user_id ?? null; // Return the actual userId from the query result, or null if not found
}

// Deletes the session with this token, so it can't be used again (logout).
export async function deleteSession(token: string): Promise<void>{
    if(typeof token !== "string"){
        return;
    }
    await pool.query(
        `DELETE FROM sessions WHERE token_hashed = $1`,
        [hashToken(token)]
    );
}

// Deletes expired sessions and password resets once an hour
// A reset is valid while its reset token still works, even after the 15-minute code itself has expired
setInterval(() => {
    pool.query("DELETE FROM sessions WHERE expires_at < now()").catch((err) => {
            console.error("Session cleanup failed:", err)
    });
    pool.query(
        `DELETE FROM password_resets
        WHERE expires_at < now() AND (token_expires_at IS NULL OR token_expires_at < now())`
    ).catch((err) => {
            console.error("Password reset cleanup failed:", err)
    });
}, 60 * 60 * 1000);
