// Rooms players walk around in: the campus map ("map") and each player's dorm ("dorm:<ownerId>"). index.ts checks
// who the socket belongs to and calls joinWorld / movePlayer / leaveWorld; dorm.ts calls joinDorm.
// Everything here is PRIVATE: This file must never import from index.ts
//
//   client -> server  join_world     {x, y}                  sent when the map opens (and again after a reconnect)
//   client -> server  move           {x, y}                  the point the player clicked (inside their room's bounds)
//   server -> client  world_state    {players: [PlayerInfo]} reply on joining a room: everyone ELSE in that room
//   server -> others  player_joined  PlayerInfo
//   server -> others  player_moved   {userId, fromX, fromY, toX, toY}
//   server -> others  player_left    {userId}
//   server -> others  player_updated {userId, username, character}   after a profile edit (profile.ts)
//   Every message stays inside the sender's room: players on the map and in a dorm never see each other.
//   Players in a block with each other (#9) never get each other's messages: they don't see each other at all.
//   setBlocked sends them player_left / player_joined when a block starts or ends while both are in one room.
//   PlayerInfo = {userId, username, character: {skin, hair, eyes}, x, y, toX, toY}

import { WebSocket } from "ws";
import { forgetChatUser } from "./chat.js";

// Must match SPEED in client/player/player.gd (pixels per second).
const PLAYER_SPEED = 300;
// Map boundary (1920x1080 - margin) must match EDGE_MARGIN_* in client/map/world_map.gd
const MAP_BOUNDS = { minX: 60, maxX: 1920 - 60, minY: 130, maxY: 1080 - 100 };
// Dorm floor must match PLAY_AREA in client/dorm/dorm_room.gd
const DORM_BOUNDS = { minX: 80, maxX: 1680, minY: 600, maxY: 900 };
// Where players appear in dorm must match the door in Club_Tiger.png
const DORM_DOOR = { minX: 80, maxX: 150, y: 640 };
const MAX_MOVES_PER_SECOND = 10;

export const MAP_ROOM = "map";

type Character = { skin: number; hair: number; eyes: number };
type Bounds = { minX: number; maxX: number; minY: number; maxY: number };
type Profile = { username: string; skin: number | null; hair: number | null; eyes: number | null };
type WorldPlayer = {
    socket: WebSocket; username: string; character: Character;
    room: string;
    fromX: number; fromY: number; toX: number; toY: number;
    movedAt: number; recentMoves: number[];
    // Players in a block with this one (either direction): they never get each other's room or chat messages.
    // Loaded from the database on join, kept up to date by setBlocked.
    hidden: Set<number>;
};

// What other clients are told about a player (matches _add_remote_player in client/room/room.gd).
type PlayerInfo = {
    userId: number; username: string; character: Character;
    x: number; y: number; toX: number; toY: number;
};

// Everyone in any room: userId -> player state (each player is in exactly one room at a time).
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

// Sends a message to everyone in one room except the players in `except`.
function broadcast(room: string, message: unknown, except: Set<number>) {
    for (const [id, p] of worldPlayers) {
        if (p.room === room && !except.has(id) && p.socket.readyState === WebSocket.OPEN) {
            send(p.socket, message);
        }
    }
}

// Sends a message from one player to everyone in their room who can see them
function broadcastFrom(userId: number, message: unknown, includeSelf: boolean) {
    const p = worldPlayers.get(userId);
    if (!p) return;
    const except = new Set(p.hidden);
    if (!includeSelf) except.add(userId);
    broadcast(p.room, message, except);
}

// The walkable area of a room
function boundsOf(room: string): Bounds {
    return room === MAP_ROOM ? MAP_BOUNDS : DORM_BOUNDS;
}

// Check if (x, y) is a real point inside the walkable area -> True
function isValidPoint(room: string, x: unknown, y: unknown): boolean {
    const b = boundsOf(room);
    return typeof x === "number" && typeof y === "number"
        && Number.isFinite(x) && Number.isFinite(y)
        && x >= b.minX && x <= b.maxX
        && y >= b.minY && y <= b.maxY;
}

// Puts a player into a room at (x, y): takes them out of the room they were in (that room gets player_left), sends
// them everyone else in the new room they can see (world_state), and tells those players they joined.
function enterRoom(socket: WebSocket, userId: number, profile: Profile, room: string, x: number, y: number,
                   hidden: Set<number>): void {
    if (worldPlayers.has(userId)) {
        broadcastFrom(userId, { type: "player_left", userId }, false);
    }
    const player: WorldPlayer = {
        socket,
        username: profile.username,
        // getUserProfile does a LEFT JOIN: users without a characters row get option 0.
        character: { skin: profile.skin ?? 0, hair: profile.hair ?? 0, eyes: profile.eyes ?? 0 },
        room,
        fromX: x, fromY: y, toX: x, toY: y,
        movedAt: Date.now(),
        recentMoves: [],
        hidden
    };
    worldPlayers.set(userId, player);

    const others: PlayerInfo[] = [];
    for (const [id, p] of worldPlayers) {
        if (id !== userId && p.room === room && !hidden.has(id)) others.push(playerInfo(id, p));
    }
    send(socket, { type: "world_state", players: others });
    broadcastFrom(userId, { type: "player_joined", ...playerInfo(userId, player) }, false);
}

// Puts a player on the campus map at the (x, y) their client picked. hidden = the players is blocked (friends.ts blockedWith)  
export function joinWorld(socket: WebSocket, userId: number, profile: Profile, x: unknown, y: unknown,
                          hidden: Set<number>): void {
    if (!isValidPoint(MAP_ROOM, x, y)) return;
    enterRoom(socket, userId, profile, MAP_ROOM, x as number, y as number, hidden);
}

// Spawn player at a random spot in front of the door
export function joinDorm(socket: WebSocket, userId: number, profile: Profile, ownerId: number,
                         hidden: Set<number>): { x: number; y: number } {
    const x = DORM_DOOR.minX + Math.random() * (DORM_DOOR.maxX - DORM_DOOR.minX);
    const y = DORM_DOOR.y;
    enterRoom(socket, userId, profile, dormRoom(ownerId), x, y, hidden);
    return { x, y };
}

// The room name of a player's dorm.
export function dormRoom(ownerId: number): string {
    return `dorm:${ownerId}`;
}

// Starts walking a player toward (x, y) from where they are now, and tells the others in their room.
export function movePlayer(socket: WebSocket, userId: number, x: unknown, y: unknown): void {
    const p = worldPlayers.get(userId);
    if (!p || p.socket !== socket) return;   // not in a room, or an old socket that was replaced
    if (!isValidPoint(p.room, x, y)) return;

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

// Takes this socket's player out of their room and tells the others there.
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

// Returns the player's username if they're in a room from this socket, otherwise null (so only they can chat)
export function getWorldUsername(socket: WebSocket, userId: number): string | null{
    const player = worldPlayers.get(userId);
    return player && player.socket === socket?player.username:null
}

// Returns the room a player is in, or null if they aren't in one
export function roomOf(userId: number): string | null {
    return worldPlayers.get(userId)?.room ?? null;
}

// Sends a chat message from a player to everyone in their room who can see them, including the sender.
export function broadcastChat(userId: number, message: unknown): void{
    broadcastFrom(userId, message, true);
}

// Sends a message to everyone in a room except the owner (dorm.ts: a new layout goes to the visitors)
export function broadcastToRoom(room: string, message: unknown, exceptUserId: number): void {
    broadcast(room, message, new Set([exceptUserId]));
}

// Saves a player's new username and look (after a profile edit)
export function updateWorldPlayer(userId: number, username: string, character: Character): void {
    const p = worldPlayers.get(userId);
    if (!p) return;
    p.username = username;
    p.character = character;
    broadcastFrom(userId, { type: "player_updated", userId, username, character }, false);
}

// Applies block (blocked = true) or unblock between two players (called by friends.ts) 
export function setBlocked(a: number, b: number, blocked: boolean): void {
    const pa = worldPlayers.get(a);
    const pb = worldPlayers.get(b);
    for (const [player, otherId] of [[pa, b], [pb, a]] as const) {
        if (!player) continue;
        if (blocked) player.hidden.add(otherId);
        else player.hidden.delete(otherId);
    }
    if (!pa || !pb || pa.room !== pb.room) return;
    const toA = blocked ? { type: "player_left", userId: b } : { type: "player_joined", ...playerInfo(b, pb) };
    const toB = blocked ? { type: "player_left", userId: a } : { type: "player_joined", ...playerInfo(a, pa) };
    if (pa.socket.readyState === WebSocket.OPEN) send(pa.socket, toA);
    if (pb.socket.readyState === WebSocket.OPEN) send(pb.socket, toB);
}
