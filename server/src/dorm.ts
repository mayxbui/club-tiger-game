// Dorm rooms (#10 room + catalog, #11 decorating, #12 visiting): entering a dorm and saving its layout. The client side
// is client/dorm/dorm_room.gd.
//
// Everything here is PRIVATE: This file must never import from index.ts
//
// Messages (must match client/dorm/dorm_room.gd):
//   client -> server   enter_dorm         {ownerId?}            no ownerId = your own dorm; someone else's = friends only
//   server -> sender   dorm_state         {ownerId, ownerName, canEdit, items: [PlacedItem], you: {x, y},
//                                          catalog?: [CatalogItem]}   catalog only for the owner
//   server -> sender   enter_dorm_result  {success: false, error}   couldn't enter (not friends, no such player)
//   client -> server   save_dorm          {items: [{itemId, x, y, z, scale}]}   the whole layout, owner only
//   server -> sender   save_dorm_result   {success, error?, items?}
//   server -> visitors dorm_updated       {items: [PlacedItem]}   everyone else in the dorm sees the new layout
//   PlacedItem  = {itemId, spriteKey, x, y, z, scale}
//   CatalogItem = {itemId, name, category, spriteKey, minScale, maxScale, owned}   owned = copies the player has
//   Entering a dorm also sends world_state (world.ts): the players already in that dorm.

import WebSocket from "ws";
import { pool } from "./db.js";
import { joinDorm, dormRoom, broadcastToRoom } from "./world.js";
import { areFriends, blockedWith } from "./friends.js";
import { checkDormLayout, type CatalogLimits } from "./validation.js";

type Profile = { username: string; skin: number | null; hair: number | null; eyes: number | null };
type CatalogRow = CatalogLimits & { itemId: number; name: string; category: string; spriteKey: string };

// At most 5 saves per 10 seconds per player, so nobody floods the database.
const MAX_SAVES = 5;
const RATE_SAVES = 10 * 1000;
const recentSaves = new Map<number, number[]>();

// Sends one JSON message to one socket (own copy, since this file can't import index.ts).
function send(socket: WebSocket, message: unknown) {
    socket.send(JSON.stringify(message));
}

// Loads the whole item catalog (there are only a few dozen items, so it's read fresh each time it's needed).
async function loadCatalog(): Promise<Map<number, CatalogRow>> {
    const result = await pool.query(
        `SELECT id, name, category, sprite_key, min_scale, max_scale, starter_qty FROM item_catalog ORDER BY category, name`
    );
    const catalog = new Map<number, CatalogRow>();
    for (const row of result.rows) {
        catalog.set(row.id, {
            itemId: row.id, name: row.name, category: row.category, spriteKey: row.sprite_key,
            minScale: row.min_scale, maxScale: row.max_scale, starterQty: row.starter_qty
        });
    }
    return catalog;
}

// Returns the dorm id of a player, making their (empty) dorm first if their account is older than dorms.
async function dormIdOf(ownerId: number): Promise<number> {
    await pool.query(`INSERT INTO dorms (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`, [ownerId]);
    return (await pool.query(`SELECT id FROM dorms WHERE user_id = $1`, [ownerId])).rows[0].id;
}

// Loads the items placed in a dorm, back to front (z, then the order they were saved in).
async function loadItems(dormId: number) {
    const result = await pool.query(
        `SELECT di.item_id, ic.sprite_key, di.x, di.y, di.z, di.scale FROM dorm_items di
        JOIN item_catalog ic ON ic.id = di.item_id WHERE di.dorm_id = $1 ORDER BY di.z, di.id`,
        [dormId]
    );
    return result.rows.map((row) => ({
        itemId: row.item_id, spriteKey: row.sprite_key, x: row.x, y: row.y, z: row.z, scale: row.scale
    }));
}

// Takes a player into a dorm: their own (no ownerId) or a friend's. Puts them in that dorm's room at the door and
// sends the room's layout; the owner also gets the catalog with how many of each item they own.
export async function enterDorm(socket: WebSocket, userId: number, ownerId: unknown, profile: Profile) {
    let owner = userId;
    if (ownerId !== undefined && ownerId !== null && ownerId !== 0) {
        if (!Number.isInteger(ownerId) || (ownerId as number) <= 0) {
            send(socket, { type: "enter_dorm_result", success: false, error: "Dorm not found." });
            return;
        }
        owner = ownerId as number;
    }
    const ownerRow = (await pool.query(`SELECT username FROM users WHERE id = $1`, [owner])).rows[0];
    if (!ownerRow) {
        send(socket, { type: "enter_dorm_result", success: false, error: "Dorm not found." });
        return;
    }
    if (owner !== userId && !(await areFriends(userId, owner))) {
        send(socket, { type: "enter_dorm_result", success: false, error: "You can only visit your friends' dorms." });
        return;
    }

    const items = await loadItems(await dormIdOf(owner));
    const canEdit = owner === userId;
    const catalog = canEdit
        ? [...(await loadCatalog()).values()].map((c) => ({
            itemId: c.itemId, name: c.name, category: c.category, spriteKey: c.spriteKey,
            minScale: c.minScale, maxScale: c.maxScale, owned: c.starterQty
        }))
        : undefined;
    const spawn = joinDorm(socket, userId, profile, owner, await blockedWith(userId));
    send(socket, { type: "dorm_state", ownerId: owner, ownerName: ownerRow.username, canEdit, items, catalog, you: spawn });
}

// Saves the owner's whole dorm layout (replacing the old one in one transaction), replies save_dorm_result, and shows
// the new layout to everyone visiting the dorm right now.
export async function saveDorm(socket: WebSocket, userId: number, items: unknown) {
    const now = Date.now();
    const times = (recentSaves.get(userId) ?? []).filter((time) => now - time < RATE_SAVES);
    if (times.length >= MAX_SAVES) {
        send(socket, { type: "save_dorm_result", success: false, error: "Saving too fast. Please wait a moment." });
        return;
    }
    times.push(now);
    recentSaves.set(userId, times);

    const catalog = await loadCatalog();
    const checked = checkDormLayout(items, catalog);
    if ("error" in checked) {
        send(socket, { type: "save_dorm_result", success: false, error: checked.error });
        return;
    }

    const dormId = await dormIdOf(userId);
    const client = await pool.connect();
    try {
        await client.query("BEGIN");
        await client.query(`DELETE FROM dorm_items WHERE dorm_id = $1`, [dormId]);
        for (const item of checked.layout) {
            await client.query(
                `INSERT INTO dorm_items (dorm_id, item_id, x, y, z, scale) VALUES ($1, $2, $3, $4, $5, $6)`,
                [dormId, item.itemId, item.x, item.y, item.z, item.scale]
            );
        }
        await client.query(`UPDATE dorms SET updated_at = now() WHERE id = $1`, [dormId]);
        await client.query("COMMIT");
    } catch (err) {
        await client.query("ROLLBACK");
        throw err;
    } finally {
        client.release();
    }

    const saved = checked.layout.map((item) => ({ ...item, spriteKey: catalog.get(item.itemId)!.spriteKey }));
    send(socket, { type: "save_dorm_result", success: true, items: saved });
    broadcastToRoom(dormRoom(userId), { type: "dorm_updated", items: saved }, userId);
}
