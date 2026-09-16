import bcrypt from "bcryptjs";
import { pool } from "./db.js";

const USERNAME_PATTERN = /^[A-Za-z0-9_]{3,20}$/;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SALT_ROUNDS = 12;

export type AuthResult =
    | { success: true; userId: number; username: string }
    | { success: false; error: string };

export async function createAccount(
    username: string,
    email: string,
    password: string
): Promise<AuthResult> {
    if (!USERNAME_PATTERN.test(username)) {
        return { success: false, error: "Username must be 3-20 characters, alphanumeric or underscore." };
    }
    if (!EMAIL_PATTERN.test(email)) {
        return { success: false, error: "Invalid email address." };
    }
    if (password.length < 8) {
        return { success: false, error: "Password must be at least 8 characters." };
    }

    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

    try {
        const result = await pool.query(
            `INSERT INTO users (username, email, password_hash)
             VALUES ($1, $2, $3)
             RETURNING id, username`,
            [username, email, passwordHash]
        );
        const row = result.rows[0];
        return { success: true, userId: row.id, username: row.username };
    } catch (err: any) {
        if (err.code === "23505") {
            return { success: false, error: "Username or email already in use." };
        }
        throw err;
    }
}

export async function login(username: string, password: string): Promise<AuthResult> {
    const result = await pool.query(
        `SELECT id, username, password_hash FROM users WHERE username = $1`,
        [username]
    );
    if (result.rowCount === 0) {
        return { success: false, error: "Invalid username or password." };
    }

    const row = result.rows[0];
    const matches = await bcrypt.compare(password, row.password_hash);
    if (!matches) {
        return { success: false, error: "Invalid username or password." };
    }

    return { success: true, userId: row.id, username: row.username };
}
