import {pool} from "./db.js"
import bcrypt from 'bcryptjs';
import {createSession} from "./sessions.js"

// Patterns for validating username and email
const USERNAME_PATTERN =  /^[A-Za-z0-9_]{3,20}$/;
// Same rule as the email_type domain in schema.sql, so an email accepted here is never rejected by the database.
const EMAIL_PATTERN = /^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$/;
const SALT_ROUND = 10;
const MAX_PASSWORD_LENGTH = 72;

// Must match the list sizes in client/player/character_presets.gd (SKINS, HAIRS, EYES)
const SKIN_COUNT = 4;
const HAIR_COUNT = 6;
const EYES_COUNT = 5;
// const TOP_COUNT = 8;
// const BOTTOM_COUNT = 8;

// The character options a player picked, each saved as a number (top and bottom come next checkpoint).
export type CharacterSelection = {
    skin?: number;
    hair?: number;
    eyes?: number;
    // top?: number;
    // bottom?: number;
}

// What createAccount and login return: the user's ID, username, token and (optionally) character on success, or an error message.
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
            if(err.constraint === "users_username_key"){
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
    // Username and password come from the client's JSON, so check they're strings first.
    if (typeof username !== "string" || typeof password !== "string") {
        return{
            success: false,
            error: "Invalid username or password."
        };
    }
    // Look up the user and their saved character in one query.
    const result = await pool.query(
        `SELECT u.id, u.username, u.password_hashed, c.skin, c.hair, c.eyes FROM users u
        LEFT JOIN characters c ON c.user_id = u.id
        WHERE u.username = $1 OR u.email = lower($1)`,
        [username.trim()]
    );
    // Both failures return the same message, so nobody can check which usernames exist.
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
        // LEFT JOIN gives null if the user has no characters row; fall back to 0 so the client always gets numbers.
        character: {
            skin: row.skin ?? 0,
            hair: row.hair ?? 0,
            eyes: row.eyes ?? 0
            // top: row.top ?? 0,
            // bottom: row.bottom ?? 0
        }
    }    
}
