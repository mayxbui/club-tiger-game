import "dotenv/config";
import{WebSocket, WebSocketServer} from "ws";
import { createAccount, login } from "./auth.js";

// Initialize the WebSocket server
const PORT = Number(process.env.PORT ?? 3103);
const wsServer = new WebSocketServer({
    port: PORT 
});

// Function to send a message to a WebSocket client
function send(socket: WebSocket, message: unknown) {
    socket.send(JSON.stringify(message));
}

// Handle new WebSocket connections and incoming messages
wsServer.on("connection", (socket) => {
    send(socket, { type: "connected", message: `You are now connected to the server` });
    socket.on("message", async (raw) => {
        let message: any;
        // Parse the incoming message and handle different message types
        try{
            message = JSON.parse(raw.toString());
            switch(message.type){
                case "create_account": {
                    const character = message.character ? message.character : {};
                    const result = await createAccount(message.username, message.email, message.password, character);
                    send(socket, {type: "create_account_result", ...result});
                    break;
                }
                case "login": {
                    const result = await login(message.username, message.password, Boolean(message.remember_me));
                    send(socket, {type: "login_result", ...result});
                    break;                    
                }
                default:
                    send(socket, {type: "error", error: `Unknown message type: ${message.type}`});
            }
        } catch(err){
            console.error("Error message:", err);
        }
    });
});

console.log((new Date()) + `Club Tiger server listening on ${PORT}`);