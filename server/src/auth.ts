import {pool} from "./db.js"
import bcrypt from 'bcryptjs';
import {createSession, hashToken} from "./sessions.js"
import { randomBytes, randomInt } from "crypto";
import { readFile } from "fs/promises";
import nodemailer from "nodemailer";

// Patterns for validating username and email
const USERNAME_PATTERN =  /^[A-Za-z0-9_]{3,20}$/;
// Same rule as the email_type domain in schema.sql
const EMAIL_PATTERN = /^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$/;
const SALT_ROUND = 10;
const MAX_PASSWORD_LENGTH = 72;

// Must match the list sizes in client/player/character_presets.gd (SKINS, HAIRS, EYES)
const SKIN_COUNT = 4;
const HAIR_COUNT = 6;
const EYES_COUNT = 5;
// const TOP_COUNT = 8;
// const BOTTOM_COUNT = 8;

const RESET_COOLDOWN = 60*1000;     // limit 1 minute
const MAX_RESET_ATTEMPTS = 5;


// The character options a player picked, each saved as a number (top and bottom come next checkpoint)
export type CharacterSelection = {
    skin?: number;
    hair?: number;
    eyes?: number;
    // top?: number;
    // bottom?: number;
}

// What createAccount and login return: the user's ID, username, token and (optionally) character on success, or an error message
export type AuthResult =
    | {success:true; userId:number; username:string; token:string, character?: CharacterSelection}
    | {success:false; error:string};

// Create a new user account function
// Validates the username, email, and password, hashes the password, and inserts the new user into the database along with their characters selection
// If successful: creates a session for the user and returns success
// If errors or if the username/email already exists: returns failure with error message
export async function createAccount(
    username: string,
    email: string,
    password: string,
    characters: CharacterSelection = {skin: 0, hair: 0, eyes: 0}    // add top and bottom here
): Promise<AuthResult>{
    // Validate username, email, and password (they come from the client's JSON, so check they're strings first)
    if (typeof username !== "string" || typeof email !== "string" || typeof password !== "string") {
        return{
            success: false,
            error: "Missing username, email, or password."
        };
    }
    if (!USERNAME_PATTERN.test(username.trim())){
        return{
            success: false,
            error: "Missing or invalid username."
        };
    }
    if (!EMAIL_PATTERN.test(email.trim().toLowerCase())){
        return{
            success:false,
            error: "Missing or invalid email address."
        };
    }
    if (password.length < 8 || password.length > MAX_PASSWORD_LENGTH){
        return{
            success: false,
            error: "Missing or invalid password. Password must be at least 8 characters long and no more than 72 characters."
        };
    }
    // Reject character values that aren't whole numbers inside each option's range (missing values default to 0 below).
    if (characters.skin !== undefined && (!Number.isInteger(characters.skin) || characters.skin < 0 || characters.skin >= SKIN_COUNT)) {
        return {
            success: false,
            error: "Invalid skin selection."
        };
    }
    if (characters.hair !== undefined && (!Number.isInteger(characters.hair) || characters.hair < 0 || characters.hair >= HAIR_COUNT)) {
        return {
            success: false,
            error: "Invalid hair selection."
        };
    }
    if (characters.eyes !== undefined && (!Number.isInteger(characters.eyes) || characters.eyes < 0 || characters.eyes >= EYES_COUNT)) {
        return {
            success: false,
            error: "Invalid eyes selection."
        };
    }
    
    // TODO: Next checkpoint : To finish top/bottom:
    // 1. Uncomment TOP_COUNT / BOTTOM_COUNT and top?/bottom? in CharacterSelection at the top of this file.
    // 2. Add top and bottom to the INSERT INTO characters below ($5, $6 with characters.top ?? 0, characters.bottom ?? 0);
    //    the characters table already has both columns.
    // 3. SELECT c.top, c.bottom in login() and getUserProfile() (index.ts), and send them in resume_session_result.
    // if (characters.top !== undefined && !Number.isInteger(characters.top) || characters.top < 0 || characters.top >= TOP_COUNT) {
    //     return {
    //         success: false,
    //         error: "Invalid top selection."
    //     };
    // }
    // if (characters.bottom !== undefined && !Number.isInteger(characters.bottom) || characters.bottom < 0 || characters.bottom >= BOTTOM_COUNT) {
    //     return {
    //         success: false,
    //         error: "Invalid bottom selection."
    //     };
    // }

    // Connect to the database and hash the password
    const client = await pool.connect();
    const passwordHash = await bcrypt.hash(password, SALT_ROUND);

    // Insert the new user and their characters selection into the database
    try{
        await client.query("BEGIN")
        const result = await client.query(
            `INSERT INTO users(username, email, password_hashed)
            VALUES ($1, $2, $3)
            RETURNING id, username`,
            [username.trim(), email.trim().toLowerCase(), passwordHash]
        );
        const row = result.rows[0];
        await client.query(
            `INSERT INTO characters (user_id, skin, hair, eyes)
            VALUES($1, $2, $3, $4)`,
            [row.id, characters.skin ?? 0, characters.hair ?? 0, characters.eyes ?? 0]
        );
        // Every account gets its (empty) dorm in the same transaction, since dorms is 1:1 with users.
        await client.query(
            `INSERT INTO dorms (user_id) VALUES ($1)`,
            [row.id]
        );

        // Commit first, so the users row exists before createSession (which uses a different connection) points to it.
        await client.query("COMMIT");

        // The account is saved at this point. If the session can't be created, don't report a failed signup
        // (retrying would say the username already exists); ask the player to sign in instead.
        try{
            const token = await createSession(row.id, false);
            return{
                success: true,
                userId: row.id,
                username: row.username,
                token
            };
        } catch (err){
            console.error("Account created but session failed:", err);
            return{
                success: false,
                error: "Account created. Please sign in."
            };
        }
    } catch (err: any){
        await client.query("ROLLBACK");
        // A duplicate username or email tells the player which one is taken; any other error goes to index.ts.
        if(err.code === "23505" && err.constraint){
            // users_username_lower_key (schema.sql) also blocks names that differ only in capitals, e.g. "May" vs "may".
            if(err.constraint === "users_username_key" || err.constraint === "users_username_lower_key"){
                return{
                    success: false,
                    error: "Username already exists."
                }
            }
            if(err.constraint === "users_email_key"){
                return{
                    success: false,
                    error: "Email already exists."
                }
            }
        }
        throw err;
    } finally{
        client.release();
    }
}

// Login function
// Checks if the username exists and if the password matches the hashed password in the database
// If successful: creates a session for the user and returns success
// If errors or if the username/password is incorrect: returns failure with error message
export async function login(
    username: string,
    password: string,
    rememberMe: boolean
): Promise<AuthResult>{
    // Username and password come from the client's JSON, so check they're strings first
    if (typeof username !== "string" || typeof password !== "string") {
        return{
            success: false,
            error: "Invalid username or password."
        };
    }
    // Look up the user and their saved character in one query. Usernames are unique ignoring capitals, so sign-in ignores them too
    const result = await pool.query(
        `SELECT u.id, u.username, u.password_hashed, c.skin, c.hair, c.eyes FROM users u
        LEFT JOIN characters c ON c.user_id = u.id
        WHERE lower(u.username) = lower($1) OR u.email = lower($1)`,
        [username.trim()]
    );
    // Both failures return the same message, so nobody can check which usernames exist
    if (result.rows.length === 0){
        return{
            success: false,
            error: "Invalid username or password."
        };
    }
    const row = result.rows[0];
    const matches = await bcrypt.compare(password, row.password_hashed);
    if(!matches){
            return{
                success: false,
                error: "Invalid username or password."
        };
    }
    const token = await createSession(row.id, rememberMe);
    return{
        success:true,
        userId: row.id,
        username: row.username,
        token,
        character: {
            skin: row.skin ?? 0,
            hair: row.hair ?? 0,
            eyes: row.eyes ?? 0
            // top: row.top ?? 0,
            // bottom: row.bottom ?? 0
        }
    }    
}

// ============================== PASSWORD RESET ==============================
const INVALID_CODE_ERROR = "Invalid or expired code.";
const RESET_EXPIRED_ERROR = "Your reset expired. Please request a new code.";
const RESET_EMAIL_TEMPLATE = new URL("../src/data/reset-password.html", import.meta.url);
const SMTP_PORT = Number(process.env.SMTP_PORT ?? 465);
const mailer = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: SMTP_PORT,
    secure: SMTP_PORT === 465,  // 465 uses TLS from the start; 587 upgrades with STARTTLS instead
    auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS
    }
});
// Logs the mail settings this server actually loaded (never the password), so a missing .env value shows up at startup.
console.log(`[reset] SMTP host=${process.env.SMTP_HOST || "(missing)"} port=${SMTP_PORT} ` +
    `user=${process.env.SMTP_USER || "(missing)"} pass=${process.env.SMTP_PASS ? "(set)" : "(missing)"} ` +
    `from=${process.env.MAIL_FROM || "(missing)"}`);

// Emails a 6-digit reset code to the account with this email; returns nothing
export async function requestPasswordReset(email: string): Promise<void> {
    // The [reset] logs below only go to the server log (journalctl); the player always sees the same reply.
    if (typeof email !== "string") {
        console.log("[reset] request skipped: email is not a string");
        return;
    }
    email = email.trim().toLowerCase();
    if (!EMAIL_PATTERN.test(email)) {
        console.log("[reset] request skipped: invalid email format");
        return;
    }

    const result = await pool.query(
        `SELECT u.id, r.created_at FROM users u
        LEFT JOIN password_resets r ON r.user_id = u.id
        WHERE u.email = $1`,
        [email]
    );
    if (result.rows.length === 0) {
        console.log(`[reset] request skipped: no account with email ${email}`);
        return;
    }
    const { id: userId, created_at: lastSentAt } = result.rows[0];
    if (lastSentAt && Date.now() - lastSentAt.getTime() < RESET_COOLDOWN) {
        console.log(`[reset] request skipped: user ${userId} already got an email less than a minute ago`);
        return;
    }

    // randomInt is cryptographically random
    const code = randomInt(0, 1_000_000).toString().padStart(6, "0");
    const codeHash = await bcrypt.hash(code, SALT_ROUND);

    // A new request replaces the old code and cancels any reset token handed out for it.
    await pool.query(
        `INSERT INTO password_resets (user_id, code_hashed, expires_at)
        VALUES ($1, $2, now() + interval '15 minutes')
        ON CONFLICT (user_id) DO UPDATE SET
            code_hashed = EXCLUDED.code_hashed, attempts = 0, created_at = now(),
            expires_at = EXCLUDED.expires_at, reset_token_hashed = NULL, token_expires_at = NULL`,
        [userId, codeHash]
    );
    try {
        console.log(`[reset] sending code to user ${userId} (${email})`);
        await sendResetEmail(email, code);
        console.log(`[reset] email sent to user ${userId}`);
    } catch (err) {
        console.error("Password reset email failed:", err);
        await pool.query(`DELETE FROM password_resets WHERE user_id = $1`, [userId]);
    }
}

// Sends the reset email
async function sendResetEmail(to: string, code: string): Promise<void> {
    const template = await readFile(RESET_EMAIL_TEMPLATE, "utf-8");
    await mailer.sendMail({
        from: process.env.MAIL_FROM,
        to,
        subject: "Club Tiger | Confirm your email address",
        html: template.replaceAll("{{CODE}}", code),
        text: `Your Club Tiger verification code is ${code}. It expires in 15 minutes. ` +
              `If you didn't ask to reset your password, you can ignore this email.`
    });
}

// Checks a player's 6-digit code and, if it's right, returns a one-time reset token for the new-password screen
export async function verifyResetCode(email: string, code: string): Promise<
    | {success: true; resetToken: string}
    | {success: false; error: string}> {
    if (typeof email !== "string" || typeof code !== "string") {
        return {success: false, error: INVALID_CODE_ERROR};
    }
    email = email.trim().toLowerCase();
    code = code.trim();
    if (!/^\d{6}$/.test(code)) {
        return {success: false, error: INVALID_CODE_ERROR};
    }

    // Count the guess first, so guesses sent at the same time can't all get past it
    const result = await pool.query(
        `UPDATE password_resets r SET attempts = r.attempts + 1
        FROM users u
        WHERE u.id = r.user_id AND u.email = $1 AND r.expires_at > now() AND r.attempts < $2
        RETURNING r.id, r.code_hashed`,
        [email, MAX_RESET_ATTEMPTS]
    );
    if (result.rows.length === 0) {
        return {success: false, error: INVALID_CODE_ERROR};
    }
    const row = result.rows[0];
    if (!(await bcrypt.compare(code, row.code_hashed))) {
        return {success: false, error: INVALID_CODE_ERROR};
    }

    const resetToken = randomBytes(32).toString("hex");
    await pool.query(
        `UPDATE password_resets SET reset_token_hashed = $1, token_expires_at = now() + interval '10 minutes'
        WHERE id = $2`,
        [hashToken(resetToken), row.id]
    );
    return {success: true, resetToken};
}

// Sets a new password with a valid reset token, then logs account out
export async function resetPassword(resetToken: string, newPassword: string): Promise<
    | {success: true}
    | {success: false; error: string}> {
    if (typeof resetToken !== "string" || typeof newPassword !== "string") {
        return {success: false, error: RESET_EXPIRED_ERROR};
    }
    // Checked before the database
    if (newPassword.length < 8 || newPassword.length > MAX_PASSWORD_LENGTH) {
        return {
            success: false,
            error: "Password must be at least 8 characters long and no more than 72 characters."
        };
    }
    const passwordHash = await bcrypt.hash(newPassword, SALT_ROUND);

    const client = await pool.connect();
    try {
        await client.query("BEGIN");
        const result = await client.query(
            `DELETE FROM password_resets
            WHERE reset_token_hashed = $1 AND token_expires_at > now()
            RETURNING user_id`,
            [hashToken(resetToken)]
        );
        if (result.rows.length === 0) {
            await client.query("ROLLBACK");
            return {success: false, error: RESET_EXPIRED_ERROR};
        }
        const userId = result.rows[0].user_id;
        await client.query(
            `UPDATE users SET password_hashed = $1 WHERE id = $2`,
            [passwordHash, userId]
        );
        // Logs out every device, including "remember me"
        await client.query(`DELETE FROM sessions WHERE user_id = $1`, [userId]);
        await client.query("COMMIT");
        return {success: true};
    } catch (err) {
        await client.query("ROLLBACK");
        throw err;
    } finally {
        client.release();
    }
}
