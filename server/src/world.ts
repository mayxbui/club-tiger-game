// Multiplayer map: index.ts checks who the socket belongs to and calls joinWorld / movePlayer / leaveWorld and
// everything else here is PRIVATE: This file must never import from index.ts

    //   client -> server  join_world  {x, y}                  sent when the map opens (and again after a reconnect)
    //   client -> server  move        {x, y}                  the point the player clicked
    //   server -> client  world_state {players: [PlayerInfo]} reply to join_world: everyone ELSE on the map
    //   server -> others  player_joined  PlayerInfo
    //   server -> others  player_moved   {userId, fromX, fromY, toX, toY}
    //   server -> others  player_left    {userId}
    //   server -> others  player_updated {userId, username, character}   after a profile edit (profile.ts)
    //   Players in a block with each other (#9) never get each other's messages: they don't see each other at all.
    //   setBlocked sends them player_left / player_joined when a block starts or ends while both are on the map.
    //   PlayerInfo = {userId, username, character: {skin, hair, eyes}, x, y, toX, toY}

import { WebSocket } from "ws";
import { forgetChatUser } from "./chat.js";

// Must match SPEED in client/player/player.gd (pixels per second).
const PLAYER_SPEED = 300;
// World boundary: 1920x1080 minus margin, so the character (head above, name tag below) is never cut off at the screen edge. Must match EDGE_MARGIN in client/map/world_map.gd.
const MAP_BOUNDS = { minX: 60, maxX: 1920 - 60, minY: 130, maxY: 1080 - 100 };
const MAX_MOVES_PER_SECOND = 10;

type Character = { skin: number; hair: number; eyes: number };
type WorldPlayer = {
    socket: WebSocket; username: string; character: Character;
    fromX: number; fromY: number; toX: number; toY: number;
    movedAt: number; recentMoves: number[];
    // Players in a block with this one (either direction): they never get each other's map or chat messages.
    // Loaded from the database on join, kept up to date by setBlocked.
    hidden: Set<number>;
};

// What other clients are told about a player (matches _add_remote_player in client/map/world_map.gd).
type PlayerInfo = {
    userId: number; username: string; character: Character;
    x: number; y: number; toX: number; toY: number;
};

// Everyone currently on the map: userId -> player state on the map.
const worldPlayers = new Map<number, WorldPlayer>();

// Sends one message to one socket as JSON.
function send(socket: WebSocket, message: unknown) {
    socket.send(JSON.stringify(message));
}

// Works out where a player is right now from where and when they started walking
function currentPosition(p: WorldPlayer): { x: number; y: number } {
    const distance = Math.hypot(p.toX - p.fromX, p.toY - p.fromY);
    const walked = Math.min(PLAYER_SPEED * (Date.now() - p.movedAt) / 1000, distance);
    const ratio = distance === 0 ? 1 : walked / distance;
    return {
        x: p.fromX + (p.toX - p.fromX) * ratio,
        y: p.fromY + (p.toY - p.fromY) * ratio
    };
}

// Builds what other clients are told about a player, with their position right now.
function playerInfo(userId: number, p: WorldPlayer): PlayerInfo {
    const position = currentPosition(p);
    return {
        userId,
        username: p.username,
        character: p.character,
        x: position.x,
        y: position.y,
        toX: p.toX,
        toY: p.toY
    };
}

// Sends a message to everyone on the map except the players.
function broadcast(message: unknown, except: Set<number>) {
    for (const [id, p] of worldPlayers) {
        if (!except.has(id) && p.socket.readyState === WebSocket.OPEN) {
            send(p.socket, message);
        }
    }
}

// True if (x, y) is a real point inside the map
function isValidPoint(x: unknown, y: unknown): boolean {
    return typeof x === "number" && typeof y === "number"
        && Number.isFinite(x) && Number.isFinite(y)
        && x >= MAP_BOUNDS.minX && x <= MAP_BOUNDS.maxX
        && y >= MAP_BOUNDS.minY && y <= MAP_BOUNDS.maxY;
}

// Sends a message from one player to everyone on the map who can see them: never to players in their hidden set,
// and to the player themself only if includeSelf.
function broadcastFrom(userId: number, message: unknown, includeSelf: boolean) {
    const except = new Set(worldPlayers.get(userId)?.hidden ?? []);
    if (!includeSelf) except.add(userId);
    broadcast(message, except);
}

// Puts a player on the map at (x, y), sends them everyone else they can see (world_state) and tells those players they joined.
// hidden = the players in a block with them (friends.ts blockedWith).
export function joinWorld(
    socket: WebSocket,
    userId: number,
    profile: { username: string; skin: number | null; hair: number | null; eyes: number | null },
    x: unknown,
    y: unknown,
    hidden: Set<number>
): void {
    if (!isValidPoint(x, y)) return;
    const startX = x as number;
    const startY = y as number;

    const player: WorldPlayer = {
        socket,
        username: profile.username,
        // getUserProfile do LEFT JOIN: user without a characters are set with option 0.
        character: { skin: profile.skin ?? 0, hair: profile.hair ?? 0, eyes: profile.eyes ?? 0 },
        fromX: startX, fromY: startY, toX: startX, toY: startY,
        movedAt: Date.now(),
        recentMoves: [],
        hidden
    };
    worldPlayers.set(userId, player);

    const others: PlayerInfo[] = [];
    for (const [id, p] of worldPlayers) {
        if (id !== userId && !hidden.has(id)) others.push(playerInfo(id, p));
    }
    send(socket, { type: "world_state", players: others });
    broadcastFrom(userId, { type: "player_joined", ...playerInfo(userId, player) }, false);
}

// Starts walking a player toward (x, y) from where they are now, and tells the others.
export function movePlayer(socket: WebSocket, userId: number, x: unknown, y: unknown): void {
    const p = worldPlayers.get(userId);
    if (!p || p.socket !== socket) return;   // not on the map, or an old socket that was replaced
    if (!isValidPoint(x, y)) return;

    const now = Date.now();
    p.recentMoves = p.recentMoves.filter((t) => now - t < 1000);
    if (p.recentMoves.length >= MAX_MOVES_PER_SECOND) return;
    p.recentMoves.push(now);

    const position = currentPosition(p);   // where they are at the moment they clicked again
    p.fromX = position.x;
    p.fromY = position.y;
    p.toX = x as number;
    p.toY = y as number;
    p.movedAt = now;

    broadcastFrom(userId, { type: "player_moved", userId, fromX: p.fromX, fromY: p.fromY, toX: p.toX, toY: p.toY }, false);
}

// Takes this socket's player off the map and tells the others.
export function leaveWorld(socket: WebSocket): void {
    for (const [userId, p] of worldPlayers) {
        if (p.socket === socket) {
            // Tell the others before removing the player.
            broadcastFrom(userId, { type: "player_left", userId }, false);
            worldPlayers.delete(userId);
            forgetChatUser(userId);
            return;
        }
    }
}

// Returns the player's username if they're on the map from this socket, otherwise null (so only they can chat)
export function getWorldUsername(socket: WebSocket, userId: number): string | null{
    const player = worldPlayers.get(userId);
    return player && player.socket === socket?player.username:null
}

// Sends a chat message from a player to everyone on the map who can see them, including the sender, excluding blocked player
export function broadcastChat(userId: number, message: unknown): void{
    broadcastFrom(userId, message, true);
}

// Saves a player's new username and look (after a profile edit) and tells everyone else on the map, so they redraw
// that player. Do nothing if the player isn't on the map; they'll show the new look when they join.
export function updateWorldPlayer(userId: number, username: string, character: Character): void {
    const p = worldPlayers.get(userId);
    if (!p) return;
    p.username = username;
    p.character = character;
    broadcastFrom(userId, { type: "player_updated", userId, username, character }, false);
}

// If blocked = true or unblock between two players right away (called by friends.ts). The one who is on the map gets the other added to or removed from their hidden set. 
// If both are on the map, they disappear from each other's screens (player_left) or reappear where they are now (player_joined).
export function setBlocked(a: number, b: number, blocked: boolean): void {
    const pa = worldPlayers.get(a);
    const pb = worldPlayers.get(b);
    for (const [player, otherId] of [[pa, b], [pb, a]] as const) {
        if (!player) continue;
        if (blocked) player.hidden.add(otherId);
        else player.hidden.delete(otherId);
    }
    if (!pa || !pb) return;
    const toA = blocked ? { type: "player_left", userId: b } : { type: "player_joined", ...playerInfo(b, pb) };
    const toB = blocked ? { type: "player_left", userId: a } : { type: "player_joined", ...playerInfo(a, pa) };
    if (pa.socket.readyState === WebSocket.OPEN) send(pa.socket, toA);
    if (pb.socket.readyState === WebSocket.OPEN) send(pb.socket, toB);
}