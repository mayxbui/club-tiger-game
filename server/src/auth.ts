import {pool} from "./db.js"
import bcrypt from 'bcryptjs';
import {createSession} from "./sessions.js"

// Patterns for validating username and email
const USERNAME_PATTERN =  /^[A-Za-z0-9_]{3,20}$/;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SALT_ROUND = 10;

// CharacterSelection type: selection of character attributes, which can include skin, hair, and eyes. Each attribute is optional and represented as a number.
export type CharacterSelection = {
    skin?: number;
    hair?: number;
    eyes?: number;
    // top?: number;
    // bottom?: number;
}

// AuthResult type: return type for an authentication check, which can either be a success or a failure
export type AuthResult = 
    | {success:true; userId:number; username:string; token:string} 
    | {success:false; error:string};

// Create a new user account function
// Validates the username, email, and password, hashes the password, and inserts the new user into the database along with their character selection
// If successful: creates a session for the user and returns success
// If errors or if the username/email already exists: returns failure with error message
export async function createAccount(
    username: string,
    email: string,
    password: string,
    character: CharacterSelection = {}
): Promise<AuthResult>{
    // Validate username, email, and password
    if (!USERNAME_PATTERN.test(username)){
        return{
            success: false,
            error: "Missing or invalid username."
        };
    }
    if (!EMAIL_PATTERN.test(email)){
        return{
            success:false,
            error: "Missing or invalid email address."
        };
    }
    if (password.length<8){
        return{
            success: false,
            error: "Missing or invalid password. Password must be at least 8 characters long."
        };
    }

    // Connect to the database and hash the password
    const client = await pool.connect();
    const passwordHash = await bcrypt.hash(password, SALT_ROUND);

    // Insert the new user and their character selection into the database
    try{
        await client.query("BEGIN")
        const result = await client.query(
            `INSERT INTO user (username, email, password_hashed)
            VALUES ($1, $2, $3)
            RETURNING id, username`,
            [username, email, passwordHash]
        );
        const row = result.rows[0];
        await client.query(
            `INSERT INTO character (user_id, skin, hair, eyes)
            VALUES($1, $2, $3, $4)`,
            [row.id, character.skin ?? 0, character.hair ?? 0, character.eyes ?? 0]
        );

        await client.query("COMMIT");
        
        const token = await createSession(row.id, false);
        return{
            success:true,
            userId: row.id,
            username: row.username,
            token
        };
    } catch (err: any){
        await client.query("ROLLBACK");
        if(err.code === "23505"){
            return{
                success: false,
                error: "Username or email already exists."
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
    const result = await pool.query(
        `SELECT id, username, password_hashed FROM user
        WHERE username = $1`,
        [username]
    );
    if (result.rowCount === 0){
        return{
            success: false,
            error: "Username not found."
        };
    }
    const row = result.rows[0];
    const matches = await bcrypt.compare(password, row.password_hashed);
    if(!matches){
            return{
                success: false,
                error: "Incorrect password."
        };
    }
    const token = await createSession(row.id, rememberMe);
    return{
        success:true,
        userId: row.id,
        username: row.username,
        token
    }
}