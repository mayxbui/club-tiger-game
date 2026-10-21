import { WebSocket } from "ws";
import { forgetChatUser } from "./chat.js";

// Multiplayer map (logic in world.ts)
// index.ts checks who the socket belongs to and calls joinWorld / movePlayer / leaveWorld and
// everything else here is PRIVATE: This file must never import from index.ts

    //   client -> server  join_world  {x, y}                  sent when the map opens (and again after a reconnect)
    //   client -> server  move        {x, y}                  the point the player clicked
    //   server -> client  world_state {players: [PlayerInfo]} reply to join_world: everyone ELSE on the map
    //   server -> others  player_joined  PlayerInfo
    //   server -> others  player_moved   {userId, fromX, fromY, toX, toY}
    //   server -> others  player_left    {userId}
    //   PlayerInfo = {userId, username, character: {skin, hair, eyes}, x, y, toX, toY}


// Must match SPEED in client/player/player.gd (pixels per second).
const PLAYER_SPEED = 300;
const MAP_BOUNDS = { minX: 0, maxX: 1152, minY: 0, maxY: 648 };
const MAX_MOVES_PER_SECOND = 10;

type Character = { skin: number; hair: number; eyes: number };
type WorldPlayer = {
    socket: WebSocket; username: string; character: Character;
    fromX: number; fromY: number; toX: number; toY: number;
    movedAt: number; recentMoves: number[];
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

// Sends a message to everyone on the map
function broadcast(message: unknown, exceptUserId: number) {
    for (const [id, p] of worldPlayers) {
        if (id !== exceptUserId && p.socket.readyState === WebSocket.OPEN) {
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

export function joinWorld(
    socket: WebSocket,
    userId: number,
    profile: { username: string; skin: number | null; hair: number | null; eyes: number | null },
    x: unknown,
    y: unknown
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
        recentMoves: []
    };
    worldPlayers.set(userId, player);

    const others: PlayerInfo[] = [];
    for (const [id, p] of worldPlayers) {
        if (id !== userId) others.push(playerInfo(id, p));
    }
    send(socket, { type: "world_state", players: others });
    broadcast({ type: "player_joined", ...playerInfo(userId, player) }, userId);
}

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

    broadcast({ type: "player_moved", userId, fromX: p.fromX, fromY: p.fromY, toX: p.toX, toY: p.toY }, userId);
}

export function leaveWorld(socket: WebSocket): void {
    for (const [userId, p] of worldPlayers) {
        if (p.socket === socket) {
            worldPlayers.delete(userId);
            forgetChatUser(userId);
            broadcast({ type: "player_left", userId }, userId);
            return;
        }
    }
}

// Returns the player's username if they're on the map from this socket, otherwise null (so only they can chat)
export function getWorldUsername(socket: WebSocket, userId: number): string | null{
    const player = worldPlayers.get(userId);
    return player && player.socket === socket?player.username:null
}

export function broadcastToWorld(message: unknown): void{
    broadcast(message, -1);
}