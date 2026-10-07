import "dotenv/config";
import{WebSocket, WebSocketServer} from "ws";
import { createAccount, login, requestPasswordReset, verifyResetCode, resetPassword } from "./auth.js";
import { validateSession, deleteSession } from "./sessions.js";
import { pool } from "./db.js";

// Initialize the WebSocket server
const PORT = Number(process.env.PORT ?? 3103);
const wsServer = new WebSocketServer({
    port: PORT,
    // ws accepts 100 MiB messages by default (16 KB)
    maxPayload: 16 * 1024
});

// Sends a message to one client as JSON.
function send(socket: WebSocket, message: unknown) {
    socket.send(JSON.stringify(message));
}

// Remembers which logged-in user each socket belongs to. Messages (update_character, move, chat, friends) will use this userId and never trust a userId sent by the client
const socketUsers = new Map<WebSocket, number>();

// Remembers this socket as the user. 
// If the same account is already logged in on another socket, that older socket is told it was closed, so one account never shows up twice in the world.
function setSocketUser(socket: WebSocket, userId: number) {
    for (const [otherSocket, otherUserId] of socketUsers) {
        if (otherUserId === userId && otherSocket !== socket) {
            socketUsers.delete(otherSocket);
            send(otherSocket, {type: "kicked", reason: "This account logged in somewhere else."});
            otherSocket.close(4000, "Logged in elsewhere");
        }
    }
    socketUsers.set(socket, userId);
}

// Failed logins per socket
// After MAX_LOGIN_FAILURES, the socket must wait LOGIN_LOCKOUT before trying again
const MAX_LOGIN_FAILURES = 5;
const LOGIN_LOCKOUT = 30 * 1000;     // in miliseconds
const loginFailures = new Map<WebSocket, {count: number; lockedUntil: number}>();
// Times of each socket's recent password reset requests: at most MAX_RESET_REQUESTS per RESET_REQUEST_WINDOW
const MAX_RESET_REQUESTS = 3;
const RESET_REQUEST_WINDOW = 10 * 60 * 1000;
const resetRequests = new Map<WebSocket, number[]>();

// Looks up a user's username and saved character options, and throws if the user doesn't exist
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

// Handles each new client connection
wsServer.on("connection", (socket) => {
    send(socket, { type: "connected", message: `You are now connected to the server` });
    socket.on("close", () => {
        socketUsers.delete(socket);
        loginFailures.delete(socket);
        resetRequests.delete(socket);
    });
    socket.on("message", async (raw) => {
        let message: any;
        // Parse the incoming message and handle different message types
        try{
            message = JSON.parse(raw.toString());
            switch(message.type){
                // Creates the account and remembers this socket as the new user
                case "create_account": {
                    const character = message.character ? message.character : {};
                    const result = await createAccount(message.username, message.email, message.password, character);
                    if(result.success) {
                        setSocketUser(socket, result.userId);
                    }
                    send(socket, {type: "create_account_result", ...result});
                    break;
                }
                // Checks the username and password and sends back a session token
                case "login": {
                    const failures = loginFailures.get(socket);
                    if (failures && failures.lockedUntil > Date.now()) {
                        send(socket, {type: "login_result", success: false, error: "Too many failed attempts. Please wait 30 seconds and try again."});
                        break;
                    }
                    const result = await login(message.username, message.password, Boolean(message.remember_me));
                    if(result.success) {
                        loginFailures.delete(socket);
                        setSocketUser(socket, result.userId);
                    } else {
                        // The count resets to 0 when a lockout begins, so after it passes the player gets MAX_LOGIN_FAILURES more tries
                        const count = (failures?.count ?? 0) + 1;
                        const locked = count >= MAX_LOGIN_FAILURES;
                        loginFailures.set(socket, {count: locked ? 0 : count, lockedUntil: locked ? Date.now() + LOGIN_LOCKOUT : 0});
                    }
                    send(socket, {type: "login_result", ...result});
                    break;
                }
                // Checks saved tokens; if it's still valid, remembers this socket's user and sends back their username and character
                case "resume_session":{
                    const userId = await validateSession(message.token);
                    if(userId){
                        const profile = await getUserProfile(userId);
                        setSocketUser(socket, userId);
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
                // Logs the socket out: deletes its session from the database and forgets user 
                case "logout":{
                    await deleteSession(message.token);
                    socketUsers.delete(socket);
                    send(socket, {type: "logout_result", success: true});
                    break;
                }

                // Emails a reset code
                case "request_password_reset": {
                    const now = Date.now();
                    const recent = (resetRequests.get(socket) ?? []).filter((t) => now - t < RESET_REQUEST_WINDOW);
                    if (recent.length < MAX_RESET_REQUESTS) {
                        recent.push(now);
                        await requestPasswordReset(message.email);
                    }
                    resetRequests.set(socket, recent);
                    send(socket, {type: "request_password_reset_result", success: true});
                    break;
                }
                // Checks the emailed code on success the reply includes resetToken
                case "verify_reset_code": {
                    const result = await verifyResetCode(message.email, message.code);
                    send(socket, {type: "verify_reset_code_result", ...result});
                    break;
                }
                // Sets the new password
                case "reset_password": {
                    const result = await resetPassword(message.reset_token, message.new_password);
                    send(socket, {type: "reset_password_result", ...result});
                    break;
                }

                // Tells the client it sent a message type the server doesn't handle
                default:
                    send(socket, {type: "error", error: `Unknown message type: ${message.type}`});
            }
        } catch(err){
            // Logs the full error for you and sends the player a generic message, so database details aren't exposed
            console.error("Error message:", err);
            send(socket, {type: "error", error: "Something went wrong. Please try again."});
        }
    });
});

console.log((new Date()) + `Club Tiger server listening on ${PORT}`);
