import {pool} from "./db.js"
import bcrypt from 'bcryptjs';
import {createSession} from "./sessions.js"


const USERNAME_PATTERN =  /^[A-Za-z0-9_]{3,20}$/;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SALT_ROUND = 10;

export type CharacterSelection = {
    skin?: number;
    hair?: number;
    eyes?: number;
    // top?: number;
    // bottom?: number;
}

export type AuthResult = 
    {success:true; userId:number; username:string; token:string}
    | {success:false; error:string};

export async function createAccount(
    username: string,
    email: string,
    password: string,
    character: CharacterSelection = {}
): Promise<AuthResult>{
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

    const client = await pool.connect();
    const passwordHash = await bcrypt.hash(password, SALT_ROUND);

    try{
        await client.query("BEGIN")
        const result = await client.query(
            `INSERT INTO users (username, email, password_hash)
            VALUES ($1, $2, $3)
            RETURNING id, username`,
            [username, email, passwordHash]
        );
        const row = result.rows[0];
        await client.query(
            `INSERT INTO characters (user_id, skin, hair, eyes)
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


export async function login(
    username: string,
    password: string,
    rememberMe: boolean
): Promise<AuthResult>{
    const result = await pool.query(
        `SELECT id, username, password_hash FROM users
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
    const matches = await bcrypt.compare(password, row.password_hash);
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