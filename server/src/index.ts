import "dotenv/config";
import{WebSocket, WebSocketServer} from "ws";
import { createAccount, login, requestPasswordReset, verifyResetCode, resetPassword } from "./auth.js";
import { validateSession, deleteSession } from "./sessions.js";
import { pool } from "./db.js";
import { joinWorld, movePlayer, leaveWorld } from "./world.js";

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

// Remembers which logged-in user each socket belongs to.
const socketUsers = new Map<WebSocket, number>();
// The session token each socket logged in with.
const socketTokens = new Map<WebSocket, string>();

// Remembers this socket as the user (and the token it logged in with).
// One account never shows up twice in the world.
function setSocketUser(socket: WebSocket, userId: number, token: string) {
    for (const [otherSocket, otherUserId] of socketUsers) {
        if (otherUserId === userId && otherSocket !== socket) {
            const oldToken = socketTokens.get(otherSocket);
            // Only if it's a DIFFERENT token: two game windows sharing one session.txt use the same token,
            // and deleting it would also log out the socket that is logging in right now.
            if (oldToken && oldToken !== token){
                deleteSession(oldToken).catch((e) => console.error("Kick: failed to delete old session", e));
            }
            socketTokens.delete(otherSocket);
            socketUsers.delete(otherSocket);
            send(otherSocket, {type: "kicked", reason: "This account logged in somewhere else."});
            otherSocket.close(4000, "Logged in elsewhere");
        }
    }
    socketUsers.set(socket, userId);
    socketTokens.set(socket,token);
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
    // When the socket closes, take its player off the map and forget everything about it.
    socket.on("close", () => {
        leaveWorld(socket);
        socketUsers.delete(socket);
        socketTokens.delete(socket);
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
                        setSocketUser(socket, result.userId, result.token);
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
                        setSocketUser(socket, result.userId, result.token);
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
                        setSocketUser(socket, userId, message.token);
                        send(socket, {
                            type: "resume_session_result", 
                                success: true, userId: userId, 
                                username: profile.username, 
                                character:{skin: profile.skin, hair: profile.hair, eyes: profile.eyes} // TODO: next checkpoint: top: profile.top, bottom: profile.bottom
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
                    leaveWorld(socket);
                    socketUsers.delete(socket);
                    socketTokens.delete(socket);
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

                // Puts a logged-in player on the map; the userId always comes from socketUsers, never from the message.
                case "join_world": {
                    const userId = socketUsers.get(socket);
                    if (!userId) { send(socket, {type: "error", error: "Please sign in first."}); break; }
                    joinWorld(socket, userId, await getUserProfile(userId), message.x, message.y);
                    break;
                }
                // Walks the player toward the point they clicked; ignored if this socket isn't logged in.
                case "move": {
                    const userId = socketUsers.get(socket);
                    if (userId) movePlayer(socket, userId, message.x, message.y);
                    break;
                }
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
