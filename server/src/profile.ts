// Profile edits (#8 player card, edit page): change your username and/or look. The client side is
// client/player_card/edit_page.gd.
//
// Everything here is PRIVATE: This file must never import from index.ts
//
// Messages (must match client/player_card/edit_page.gd):
//   client -> server   update_profile          {username?, character?: {skin, hair, eyes}}   only the fields that changed
//   server -> sender   update_profile_result   {success, error?, username, character}
//   server -> others   player_updated          {userId, username, character}   (sent by world.ts, if on the map)

import WebSocket from "ws";
import { pool } from "./db.js";
import { checkUsername, checkCharacter } from "./validation.js";
import { updateWorldPlayer } from "./world.js";

// At most 5 profile saves per minute per player, so nobody can spam renames.
const MAX_SAVES = 5;
const RATE_SAVES = 60 * 1000;
const recentSaves = new Map<number, number[]>();

// Sends one JSON message to one socket (own copy, since this file can't import index.ts).
function send(socket: WebSocket, message: unknown) {
    socket.send(JSON.stringify(message));
}

// Tells only the sender why their save failed.
function reject(socket: WebSocket, error: string) {
    send(socket, { type: "update_profile_result", success: false, error });
}

// Saves a new username and/or look for this player, replies with the saved values, and updates them on the map.
// The username goes through the same checks as sign-up; the look must have all three parts in range.
export async function updateProfile(socket: WebSocket, userId: number, username: unknown, character: unknown) {
    if (username === undefined && character === undefined) {
        reject(socket, "Nothing to save.");
        return;
    }
    if (username !== undefined) {
        const error = checkUsername(username);
        if (error) { reject(socket, error); return; }
    }
    if (character !== undefined) {
        const error = checkCharacter(character);
        if (error) { reject(socket, error); return; }
        const c = character as Record<string, unknown>;
        if (c.skin === undefined || c.hair === undefined || c.eyes === undefined) {
            reject(socket, "Invalid character selection.");
            return;
        }
    }

    const now = Date.now();
    const times = (recentSaves.get(userId) ?? []).filter((time) => now - time < RATE_SAVES);
    if (times.length >= MAX_SAVES) {
        reject(socket, "Too many changes. Please wait a minute.");
        return;
    }
    times.push(now);
    recentSaves.set(userId, times);

    // Both updates in one transaction, so a taken username doesn't leave a half-saved profile.
    const client = await pool.connect();
    try {
        await client.query("BEGIN");
        if (username !== undefined) {
            await client.query(`UPDATE users SET username = $1 WHERE id = $2`, [(username as string).trim(), userId]);
        }
        if (character !== undefined) {
            const c = character as { skin: number; hair: number; eyes: number };
            // Upsert: older accounts might not have a characters row yet.
            await client.query(
                `INSERT INTO characters (user_id, skin, hair, eyes) VALUES ($1, $2, $3, $4)
                ON CONFLICT (user_id) DO UPDATE SET skin = $2, hair = $3, eyes = $4, updated_at = now()`,
                [userId, c.skin, c.hair, c.eyes]
            );
        }
        const saved = (await client.query(
            `SELECT u.username, c.skin, c.hair, c.eyes FROM users u
            LEFT JOIN characters c ON c.user_id = u.id WHERE u.id = $1`,
            [userId]
        )).rows[0];
        await client.query("COMMIT");

        const savedCharacter = { skin: saved.skin ?? 0, hair: saved.hair ?? 0, eyes: saved.eyes ?? 0 };
        send(socket, { type: "update_profile_result", success: true, username: saved.username, character: savedCharacter });
        updateWorldPlayer(userId, saved.username, savedCharacter);
    } catch (err: any) {
        await client.query("ROLLBACK");
        // Usernames are unique ignoring capitals (users_username_lower_key)
        if (err.code === "23505") {
            reject(socket, "That username is taken.");
            return;
        }
        throw err;
    } finally {
        client.release();
    }
}
