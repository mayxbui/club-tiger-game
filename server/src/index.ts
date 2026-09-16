import "dotenv/config";
import { WebSocket, WebSocketServer } from "ws";
import { createAccount, login } from "./auth.js";

const PORT = Number(process.env.PORT ?? 3103);

const wss = new WebSocketServer({ port: PORT });

function send(socket: WebSocket, message: unknown) {
    socket.send(JSON.stringify(message));
}

wss.on("connection", (socket) => {
    socket.on("message", async (raw) => {
        let message: any;
        try {
            message = JSON.parse(raw.toString());
        } catch {
            send(socket, { type: "error", error: "Malformed message." });
            return;
        }

        try {
            switch (message.type) {
                case "create_account": {
                    const result = await createAccount(message.username, message.email, message.password);
                    send(socket, { type: "create_account_result", ...result });
                    break;
                }
                case "login": {
                    const result = await login(message.username, message.password);
                    send(socket, { type: "login_result", ...result });
                    break;
                }
                default:
                    send(socket, { type: "error", error: `Unknown message type: ${message.type}` });
            }
        } catch (err) {
            console.error("Error handling message:", err);
            send(socket, { type: "error", error: "Internal server error." });
        }
    });
});

console.log(`Club Tiger server listening on ws://0.0.0.0:${PORT}`);
