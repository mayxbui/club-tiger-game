import "dotenv/config";
import{WebSocket, WebSocketServer} from "ws";
import { createAccount, login } from "./auth.js";
import { validateSession, deleteSession } from "./sessions.js";
import { pool } from "./db.js";

// Initialize the WebSocket server
const PORT = Number(process.env.PORT ?? 3103);
const wsServer = new WebSocketServer({
    port: PORT
});

// Sends a message to one client as JSON.
function send(socket: WebSocket, message: unknown) {
    socket.send(JSON.stringify(message));
}

// Remembers which logged-in user each socket belongs to. Later messages (update_character, move, chat,
// friends) should use this userId and never trust a userId sent by the client.
const socketUsers = new Map<WebSocket, number>();

// Looks up a user's username and saved character options, and throws if the user doesn't exist.
const getUserProfile = async (userId: number) => {
    const result = await pool.query(
        `SELECT u.username, c.skin, c.hair, c.eyes FROM users u
        LEFT JOIN characters c ON c.user_id = u.id WHERE u.id = $1`,
        [userId]
    );
    if (result.rows.length === 0) {
        throw new Error("User not found");
    }
    return result.rows[0];
};

// Handles each new client connection: greets it, forgets its user when it disconnects, and routes every incoming message by its type.
wsServer.on("connection", (socket) => {
    send(socket, { type: "connected", message: `You are now connected to the server` });
    socket.on("close", () => {
        socketUsers.delete(socket);
    });
    socket.on("message", async (raw) => {
        let message: any;
        // Parse the incoming message and handle different message types
        try{
            message = JSON.parse(raw.toString());
            switch(message.type){
                // Creates the account and remembers this socket as the new user.
                case "create_account": {
                    const character = message.character ? message.character : {};
                    const result = await createAccount(message.username, message.email, message.password, character);
                    if(result.success) {
                        socketUsers.set(socket, result.userId);
                    }
                    send(socket, {type: "create_account_result", ...result});
                    break;
                }
                // Checks the username and password and sends back a session token.
                case "login": {
                    const result = await login(message.username, message.password, Boolean(message.remember_me));
                    if(result.success) {
                        socketUsers.set(socket, result.userId);
                    }
                    send(socket, {type: "login_result", ...result});
                    break;
                }
                // Checks a saved token; if it's still valid, remembers this socket's user and sends back their username and character.
                case "resume_session":{
                    const userId = await validateSession(message.token);
                    if(userId){
                        const profile = await getUserProfile(userId);
                        socketUsers.set(socket, userId);
                        send(socket, {
                            type: "resume_session_result", 
                                success: true, userId: userId, 
                                username: profile.username, 
                                character:{skin: profile.skin, hair: profile.hair, eyes: profile.eyes} // next checkpoint: top: profile.top, bottom: profile.bottom
                            });                        
                        }else{
                            send(socket, {
                                type: "resume_session_result", success: false});
                        }
                    }                    
                    break;
                // Logs the socket out: deletes its session from the database and forgets which user it was.
                case "logout":{
                    await deleteSession(message.token);
                    socketUsers.delete(socket);
                    send(socket, {type: "logout_result", success: true});
                    break;
                }

                // TODO: reset password (client: reset_password.tscn sends {type: "request_password_reset", email}).
                // 1. schema.sql: add a password_resets table (id, user_id REFERENCES users ON DELETE CASCADE,
                //    token_hashed TEXT UNIQUE, expires_at TIMESTAMPTZ, used_at TIMESTAMPTZ) - same idea as sessions.
                // 2. auth.ts: requestPasswordReset(email) - trim + lowercase the email, look up the user; if found,
                //    make a random token (randomBytes like createSession), store its SHA-256 hash with a ~30 min
                //    expiry, and email a reset link/code (needs an email service, e.g. nodemailer + SMTP in .env).
                // 3. Here: case "request_password_reset" - ALWAYS send {type: "request_password_reset_result", success: true},
                //    even if the email doesn't exist, so nobody can use this to find out which emails have accounts.
                //    The client then shows "Success! If the email provided is associated with an account...".
                // 4. auth.ts: resetPassword(token, newPassword) - check the token is unexpired and unused, apply the
                //    same 8-72 length rule, bcrypt the new password, UPDATE users, mark the token used, and
                //    DELETE FROM sessions for that user so old logins stop working.
                // 5. Rate-limit requests per email/socket so this can't be used to spam someone's inbox.

                // Tells the client it sent a message type the server doesn't handle.
                default:
                    send(socket, {type: "error", error: `Unknown message type: ${message.type}`});
            }
        } catch(err){
            // Logs the full error for you and sends the player a generic message, so database details aren't exposed.
            console.error("Error message:", err);
            send(socket, {type: "error", error: "Something went wrong. Please try again."});
        }
    });
});

console.log((new Date()) + `Club Tiger server listening on ${PORT}`);
