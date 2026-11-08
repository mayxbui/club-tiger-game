// Chat server: checks a chat message, filters it, and sends it to everyone
// on the map.
//
// Messages (must match client/map/world_map.gd):
//   client -> server   chat           {text}
//   server -> everyone chat_message   {userId, username, text}     also sent back to the sender, so everyone
//                                                                   (including them) sees the same text. Players
//                                                                   in a block with the sender (either way) don't
//                                                                   get it (#9)
//   server -> sender   chat_rejected  {reason}                     only the sender sees why it wasn't sent

import { WebSocket } from "ws";
import { findBlockedPhrase, containsLink } from "./chatFilter.js";
import { getWorldUsername, broadcastChat } from "./world.js";

const MAX_CHAT_LENGTH = 48;   
const MAX_MESSAGES = 3;        
const RATE_CHAT = 3 * 1000;        
const recentMessages = new Map<number, number[]>();   // userId -> times of their recent messages

function send(socket: WebSocket, message: unknown ){
    socket.send(JSON.stringify(message));
}

function reject(socket: WebSocket, reason: string){
    send(socket,{
        type: "chat_rejected",
        reason: reason,
    });
}

// Cleans the message, checks length, rate limit and blocked words, then broadcasts it to everyone on the map except
// players blocked with the sender.
export function handleChat(socket: WebSocket, userId: number, chatMsg: unknown): void{
    const username = getWorldUsername(socket,userId);
    if(!username) return;
    if(typeof chatMsg!== "string") return;

    let text = chatMsg.normalize("NFC");
    text = text.replace(/[\u200B-\u200F\u202A-\u202E\u2060-\u2069\uFEFF]/g, "")    // remove invisible and direction characters
    text = text.replace(/[\u0000-\u001F\u007F]/g, " ")                             // newlines, tabs and other control characters
    text = text.replace(/\s+/g, " ").trim()                                        // many spaces -> one
    if (text.length === 0) return;
    if ([...text].length > MAX_CHAT_LENGTH){
        reject(socket, "Message is too long (max 48 characters).");
        return;
    }

    const now = Date.now()
    const times = (recentMessages.get(userId) ?? []).filter((time)=> now - time <RATE_CHAT);
    if(times.length>=MAX_MESSAGES){
        reject(socket, "Sending too many messages too fast.");
        return;
    }
    times.push(now);
    recentMessages.set(userId, times);

    // Links are mostly scams, phishing and porn spam, and players can't check them before clicking (rule R4).
    if (containsLink(text)){
        console.log(`[chat] link blocked from user ${userId}`);
        reject(socket, "Links aren't allowed in chat.");
        return;
    }

    const blocked = findBlockedPhrase(text);
    if(blocked){
        // Logged on the server only
        console.log(`[chat] blocked message from user ${userId} (matched "${blocked}")`);
        reject(socket, "Your message wasn't sent because it contains blocked words.")
        return;
    }
    broadcastChat(userId, {
        "type": "chat_message",
        userId,
        username,
        text
    })
}

// Forgets a player's rate-limit history when they leave the map (called from leaveWorld in world.ts).
export function forgetChatUser(userId: number): void{
    recentMessages.delete(userId);
}
